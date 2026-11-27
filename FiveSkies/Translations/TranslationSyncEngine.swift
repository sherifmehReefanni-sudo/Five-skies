import Foundation

enum TranslationSyncError: Error, Equatable, Sendable {
    /// No relay is configured, so nothing can be synced.
    case notConnected
    /// The translation has not been downloaded yet.
    case notDownloaded
    /// An answer did not follow the documented Content Sync shape.
    case malformed
    /// A bootstrap finished without any rows.
    case empty
}

enum TranslationSyncOutcome: Equatable, Sendable {
    /// The local copy was written. Carries the new summary.
    case updated(TranslationSummary)
    /// Quran Foundation no longer offers the resource, so the local copy was removed.
    case removed(id: Int)
}

/// Keeps offline copies of translations with Quran Foundation Content Sync, following the
/// documented client flow for the `translations` resource group:
/// bootstrap, follow `next_page_url` while `has_more`, fetch every `snapshot_url`,
/// apply row changes in ascending `sequence`, store `next_sync_token` only after the final
/// page and every snapshot were applied, re-bootstrap when the token is rejected.
/// A new copy is written only after a whole run succeeds, so a failure (or being offline)
/// always leaves the last good copy and its token in place.
actor TranslationSyncEngine {
    static let resourceGroup = "translations"
    static let perPage = 100
    static let maxPages = 2000

    typealias Progress = @Sendable (Double) -> Void

    private let client: RelayFetching?
    private let storage: TranslationStorage
    private let now: @Sendable () -> Date
    private let maxAge: TimeInterval
    private var inFlight: [Int: Task<TranslationSyncOutcome, Error>] = [:]

    init(
        client: RelayFetching?,
        storage: TranslationStorage,
        now: @escaping @Sendable () -> Date = { Date() },
        maxAge: TimeInterval = TranslationStorage.maxAge
    ) {
        self.client = client
        self.storage = storage
        self.now = now
        self.maxAge = maxAge
    }

    // MARK: - Paths

    static func resourceFilter(id: Int) -> String {
        "\(resourceGroup):\(id)"
    }

    static func bootstrapPath(id: Int) -> String {
        "/api/v4/resources/sync?bootstrap=true&resources=\(resourceFilter(id: id))&per_page=\(perPage)"
    }

    static func incrementalPath(id: Int, token: String) -> String {
        "/api/v4/resources/sync?resources=\(resourceFilter(id: id))&sync_token=\(encodeQueryValue(token))&per_page=\(perPage)"
    }

    /// Percent-encodes everything except unreserved characters, so tokens with + / = survive.
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Local state

    func summaries() -> [TranslationSummary] {
        storage.loadAll().map(\.summary)
    }

    func load(id: Int) -> StoredTranslation? {
        storage.load(id: id)
    }

    /// Deletes the local copy. The person can do this at any time.
    func remove(id: Int) throws {
        try storage.remove(id: id)
    }

    func needsRefresh(id: Int) -> Bool {
        guard let stored = storage.load(id: id) else { return false }
        return stored.summary.needsRefresh(now: now(), maxAge: maxAge)
    }

    /// IDs of downloaded translations whose last successful sync is older than the max age.
    func staleIDs() -> [Int] {
        let date = now()
        return storage.loadAll()
            .filter { $0.summary.needsRefresh(now: date, maxAge: maxAge) }
            .map(\.id)
    }

    // MARK: - Sync entry points

    /// First download of a translation: a full bootstrap.
    func download(_ info: TranslationInfo, progress: Progress? = nil) async throws -> TranslationSyncOutcome {
        let metadata = Metadata(name: info.name, authorName: info.authorName, languageName: info.languageName)
        return try await joined(id: info.id) {
            try await self.bootstrap(id: info.id, metadata: metadata, progress: progress)
        }
    }

    /// Incremental sync of a downloaded translation (bootstrap if it has no token).
    func sync(id: Int, progress: Progress? = nil) async throws -> TranslationSyncOutcome {
        try await joined(id: id) {
            try await self.performSync(id: id, progress: progress)
        }
    }

    /// Syncs only when the copy is older than the max age. Returns nil when nothing was due.
    func refreshIfNeeded(id: Int, progress: Progress? = nil) async throws -> TranslationSyncOutcome? {
        guard needsRefresh(id: id) else { return nil }
        return try await sync(id: id, progress: progress)
    }

    // MARK: - Flow

    private struct Metadata: Sendable {
        let name: String
        let authorName: String?
        let languageName: String?
    }

    /// Runs one job per translation at a time; a second caller waits for the same run.
    private func joined(
        id: Int,
        _ work: @escaping @Sendable () async throws -> TranslationSyncOutcome
    ) async throws -> TranslationSyncOutcome {
        if let running = inFlight[id] {
            return try await running.value
        }
        let task = Task { try await work() }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }

    private func performSync(id: Int, progress: Progress?) async throws -> TranslationSyncOutcome {
        guard client != nil else { throw TranslationSyncError.notConnected }
        guard let existing = storage.load(id: id) else { throw TranslationSyncError.notDownloaded }
        let metadata = Metadata(name: existing.name, authorName: existing.authorName, languageName: existing.languageName)
        guard let token = existing.syncToken, !token.isEmpty else {
            return try await bootstrap(id: id, metadata: metadata, progress: progress)
        }
        do {
            return try await incremental(existing: existing, token: token, progress: progress)
        } catch {
            guard ContentSyncErrorCode.isTokenRejection(error) else { throw error }
            // The server rejected the token: rebuild this resource from current public content.
            // The old copy stays on disk until the new one is complete.
            return try await bootstrap(id: id, metadata: metadata, progress: progress)
        }
    }

    private func bootstrap(id: Int, metadata: Metadata, progress: Progress?) async throws -> TranslationSyncOutcome {
        guard let client else { throw TranslationSyncError.notConnected }
        progress?(0.05)
        let run = try await fetchAllPages(client: client, firstPath: Self.bootstrapPath(id: id), progress: progress)
        var rows = TranslationRowSet()
        if try await apply(run.mutations, id: id, to: &rows, client: client, progress: progress) == .removed {
            return try removeLocal(id: id)
        }
        guard !rows.rows.isEmpty else { throw TranslationSyncError.empty }
        return try commit(id: id, metadata: metadata, token: run.token, rows: rows, progress: progress)
    }

    private func incremental(existing: StoredTranslation, token: String, progress: Progress?) async throws -> TranslationSyncOutcome {
        guard let client else { throw TranslationSyncError.notConnected }
        progress?(0.05)
        let path = Self.incrementalPath(id: existing.id, token: token)
        let run = try await fetchAllPages(client: client, firstPath: path, progress: progress)
        var rows = TranslationRowSet(rows: existing.rows)
        if try await apply(run.mutations, id: existing.id, to: &rows, client: client, progress: progress) == .removed {
            return try removeLocal(id: existing.id)
        }
        let metadata = Metadata(name: existing.name, authorName: existing.authorName, languageName: existing.languageName)
        return try commit(id: existing.id, metadata: metadata, token: run.token ?? token, rows: rows, progress: progress)
    }

    private struct PageRun {
        let mutations: [SyncMutation]
        let token: String?
    }

    /// Follows `next_page_url` until `has_more` is false. The token comes from the final page only.
    private func fetchAllPages(client: RelayFetching, firstPath: String, progress: Progress?) async throws -> PageRun {
        var path = firstPath
        var visited: Set<String> = []
        var mutations: [SyncMutation] = []
        for page in 0..<Self.maxPages {
            try Task.checkCancellation()
            guard visited.insert(path).inserted else { throw TranslationSyncError.malformed }
            let response: SyncResponse = try await client.get(relativePath: path)
            mutations.append(contentsOf: response.sync.mutations)
            progress?(min(0.1 + 0.05 * Double(page + 1), 0.5))
            guard response.sync.hasMore else {
                return PageRun(mutations: mutations, token: response.sync.nextSyncToken)
            }
            guard let next = response.sync.nextPageUrl, !next.isEmpty else {
                throw TranslationSyncError.malformed
            }
            path = next
        }
        throw TranslationSyncError.malformed
    }

    private enum ApplyResult {
        case applied
        case removed
    }

    /// Applies this resource's mutations in ascending `sequence` order.
    private func apply(
        _ mutations: [SyncMutation],
        id: Int,
        to rows: inout TranslationRowSet,
        client: RelayFetching,
        progress: Progress?
    ) async throws -> ApplyResult {
        let relevant = mutations
            .filter { $0.resourceGroup == Self.resourceGroup && $0.resourceId == id }
            .sorted { $0.sequence < $1.sequence }
        for mutation in relevant {
            switch mutation.type {
            case .resourceCreate, .resourceInvalidate:
                guard let snapshotPath = mutation.snapshotUrl, !snapshotPath.isEmpty else {
                    throw TranslationSyncError.malformed
                }
                let snapshot: SnapshotResponse
                do {
                    snapshot = try await client.get(relativePath: snapshotPath)
                } catch {
                    if ContentSyncErrorCode.isSnapshotNotFound(error) {
                        return .removed
                    }
                    throw error
                }
                guard snapshot.resourceGroup == Self.resourceGroup, snapshot.resourceId == id else {
                    throw TranslationSyncError.malformed
                }
                rows = try TranslationRowSet(snapshot: snapshot.records)
                progress?(0.9)
            case .resourceDelete:
                return .removed
            case .resourceUpdate, .unknown:
                // A freshness marker only: keep the rows.
                continue
            case .rowCreate, .rowUpdate:
                guard let data = mutation.data,
                      let verseKey = data.verseKey, !verseKey.isEmpty,
                      let text = data.text,
                      let key = mutation.recordKey ?? data.id.map({ String($0) })
                else {
                    throw TranslationSyncError.malformed
                }
                rows.upsert(key: key, row: StoredTranslationRow(verseKey: verseKey, text: text))
            case .rowDelete:
                guard let key = mutation.recordKey else { throw TranslationSyncError.malformed }
                rows.delete(key: key)
            }
        }
        return .applied
    }

    private func commit(id: Int, metadata: Metadata, token: String?, rows: TranslationRowSet, progress: Progress?) throws -> TranslationSyncOutcome {
        let stored = StoredTranslation(
            id: id,
            name: metadata.name,
            authorName: metadata.authorName,
            languageName: metadata.languageName,
            lastSyncedAt: now(),
            syncToken: token,
            rows: rows.rows
        )
        try storage.save(stored)
        progress?(1)
        return .updated(stored.summary)
    }

    private func removeLocal(id: Int) throws -> TranslationSyncOutcome {
        try storage.remove(id: id)
        return .removed(id: id)
    }
}

/// Rows of one translation, with one row per verse key whatever the record key scheme is.
struct TranslationRowSet: Sendable {
    private(set) var rows: [String: StoredTranslationRow]
    private var keyByVerse: [String: String]

    init(rows: [String: StoredTranslationRow] = [:]) {
        self.rows = rows
        var index: [String: String] = [:]
        for (key, row) in rows {
            index[row.verseKey] = key
        }
        keyByVerse = index
    }

    /// Rows of a snapshot, keyed by the record id as a string.
    init(snapshot records: [TranslationRecord]) throws {
        var rows: [String: StoredTranslationRow] = [:]
        for record in records {
            guard let id = record.id, let verseKey = record.verseKey, !verseKey.isEmpty, let text = record.text else {
                throw TranslationSyncError.malformed
            }
            rows[String(id)] = StoredTranslationRow(verseKey: verseKey, text: text)
        }
        self.init(rows: rows)
    }

    /// Inserts or replaces a whole row (ROW_UPDATE data is the complete row).
    mutating func upsert(key: String, row: StoredTranslationRow) {
        if let old = rows[key], old.verseKey != row.verseKey, keyByVerse[old.verseKey] == key {
            keyByVerse[old.verseKey] = nil
        }
        if let other = keyByVerse[row.verseKey], other != key {
            rows[other] = nil
        }
        rows[key] = row
        keyByVerse[row.verseKey] = key
    }

    /// Deletes one row by record key, or by verse key when the record key is one.
    mutating func delete(key: String) {
        if let old = rows.removeValue(forKey: key) {
            if keyByVerse[old.verseKey] == key {
                keyByVerse[old.verseKey] = nil
            }
            return
        }
        if let other = keyByVerse.removeValue(forKey: key) {
            rows[other] = nil
        }
    }
}
