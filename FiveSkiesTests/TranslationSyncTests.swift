import XCTest
@testable import FiveSkies

/// A relay that answers from canned JSON by exact relative path. Unknown paths act as offline.
/// Serving a path again replaces its answer.
final class FakeRelay: RelayFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Result<Data, Error>] = [:]
    private var log: [String] = []

    func serve(_ path: String, json: String) {
        lock.withLock { answers[path] = .success(Data(json.utf8)) }
    }

    func fail(_ path: String, with error: Error) {
        lock.withLock { answers[path] = .failure(error) }
    }

    var requested: [String] {
        lock.withLock { log }
    }

    func data(relativePath: String) async throws -> Data {
        let result: Result<Data, Error>? = lock.withLock {
            log.append(relativePath)
            return answers[relativePath]
        }
        guard let result else { throw RelayError.transport }
        return try result.get()
    }
}

/// A clock the test can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

final class TranslationSyncTests: XCTestCase {
    private static let id = 20
    private static let day: TimeInterval = 24 * 60 * 60
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static let bootstrapPath = "/api/v4/resources/sync?bootstrap=true&resources=translations:20&per_page=100"
    private static let secondPagePath = "/api/v4/resources/sync?cursor=sample-cursor-2&per_page=100&resources=translations%3A20"
    private static let snapshotPath = "/api/v4/resources/snapshots/translations/20"

    private var directory: URL!
    private var storage: TranslationStorage!
    private var relay: FakeRelay!
    private var clock: TestClock!
    private var engine: TranslationSyncEngine!

    private let info = TranslationInfo(id: 20, name: "Sample Translation", authorName: "Sample Translator", languageName: "english")

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranslationSyncTests-\(UUID().uuidString)", isDirectory: true)
        storage = TranslationStorage(directory: directory)
        relay = FakeRelay()
        clock = TestClock(Self.start)
        let clock = self.clock
        engine = TranslationSyncEngine(client: relay, storage: storage, now: { clock?.now ?? Date() })
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        engine = nil
        relay = nil
        storage = nil
        directory = nil
    }

    // MARK: - Canned JSON, shaped like the documented Content Sync answers

    private static func mutation(
        sequence: Int,
        type: String,
        resourceId: Int = 20,
        recordKey: String? = nil,
        data: String = "null",
        snapshotURL: String? = nil
    ) -> String {
        let key = recordKey.map { "\"\($0)\"" } ?? "null"
        let recordType = recordKey == nil ? "null" : "\"translation\""
        let snapshot = snapshotURL.map { "\"\($0)\"" } ?? "null"
        return """
        {"sequence":\(sequence),"type":"\(type)","resource_group":"translations","resource_id":\(resourceId),\
        "resource_content_id":\(resourceId),"record_type":\(recordType),"record_key":\(key),"source_record_id":null,\
        "changed_at":"2026-01-01T00:00:00Z","data":\(data),"snapshot_url":\(snapshot),"unavailable_reason":null}
        """
    }

    private static func page(hasMore: Bool, next: String?, token: String?, mutations: [String]) -> String {
        let nextJSON = next.map { "\"\($0)\"" } ?? "null"
        let tokenJSON = token.map { "\"\($0)\"" } ?? "null"
        return """
        {"sync":{"sync_until_sequence":900,"has_more":\(hasMore),"next_page_url":\(nextJSON),\
        "next_sync_token":\(tokenJSON),"mutations":[\(mutations.joined(separator: ","))]}}
        """
    }

    private static func row(id: Int, verse: String, text: String) -> String {
        "{\"id\":\(id),\"verse_key\":\"\(verse)\",\"text\":\"\(text)\"}"
    }

    private static func snapshot(_ rows: [String]) -> String {
        """
        {"resource_group":"translations","resource_id":20,"resource_content_id":20,"schema_version":1,\
        "sync_sequence":900,"records":[\(rows.joined(separator: ","))]}
        """
    }

    /// Two bootstrap pages: a RESOURCE_CREATE with a snapshot, then a row update, a
    /// freshness marker and a row for another resource that must be ignored.
    private func serveTwoPageBootstrap() {
        relay.serve(Self.bootstrapPath, json: Self.page(
            hasMore: true,
            next: Self.secondPagePath,
            token: nil,
            mutations: [Self.mutation(sequence: 101, type: "RESOURCE_CREATE", snapshotURL: Self.snapshotPath)]
        ))
        relay.serve(Self.secondPagePath, json: Self.page(
            hasMore: false,
            next: nil,
            token: "sample-token-1",
            mutations: [
                Self.mutation(sequence: 103, type: "RESOURCE_UPDATE"),
                Self.mutation(sequence: 102, type: "ROW_UPDATE", recordKey: "9002",
                              data: Self.row(id: 9002, verse: "1:2", text: "sample text 2 revised")),
                Self.mutation(sequence: 104, type: "ROW_CREATE", resourceId: 99, recordKey: "5",
                              data: Self.row(id: 5, verse: "1:1", text: "sample text other"))
            ]
        ))
        relay.serve(Self.snapshotPath, json: Self.snapshot([
            Self.row(id: 9001, verse: "1:1", text: "sample text 1"),
            Self.row(id: 9002, verse: "1:2", text: "sample text 2"),
            Self.row(id: 9003, verse: "1:3", text: "sample text 3 <sup foot_note=77>1</sup>")
        ]))
    }

    private func incrementalPath(token: String) -> String {
        "/api/v4/resources/sync?resources=translations:20&sync_token=\(token)&per_page=100"
    }

    private func bootstrapped() async throws -> StoredTranslation {
        serveTwoPageBootstrap()
        _ = try await engine.download(info)
        return try XCTUnwrap(storage.load(id: Self.id))
    }

    // MARK: - Bootstrap

    func testBootstrapFollowsPagesAppliesSnapshotThenRowsAndStoresFinalToken() async throws {
        serveTwoPageBootstrap()
        let outcome = try await engine.download(info)

        XCTAssertEqual(relay.requested, [Self.bootstrapPath, Self.secondPagePath, Self.snapshotPath])
        let stored = try XCTUnwrap(storage.load(id: Self.id))
        XCTAssertEqual(outcome, .updated(stored.summary))
        XCTAssertEqual(stored.syncToken, "sample-token-1")
        XCTAssertEqual(stored.lastSyncedAt, Self.start)
        XCTAssertEqual(stored.name, "Sample Translation")
        XCTAssertEqual(stored.authorName, "Sample Translator")
        XCTAssertEqual(stored.languageName, "english")

        let verses = stored.versesByKey()
        XCTAssertEqual(verses.count, 3)
        XCTAssertEqual(verses["1:1"], "sample text 1")
        XCTAssertEqual(verses["1:2"], "sample text 2 revised")
        // Stored exactly as sent; markup is removed only for display.
        XCTAssertEqual(verses["1:3"], "sample text 3 <sup foot_note=77>1</sup>")

        let displayCopy = await engine.displayCopy(id: Self.id)
        let display = try XCTUnwrap(displayCopy)
        XCTAssertEqual(display.verses["1:3"], "sample text 3 ")
        XCTAssertEqual(display.verses["1:1"], "sample text 1")
    }

    func testStoredFileIsExcludedFromBackupAndRemovable() async throws {
        _ = try await bootstrapped()
        let url = storage.fileURL(for: Self.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(TranslationStorage.isExcludedFromBackup(url))
        let summaries = await engine.summaries()
        XCTAssertEqual(summaries.map(\.id), [Self.id])

        try await engine.remove(id: Self.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let after = await engine.summaries()
        XCTAssertTrue(after.isEmpty)
    }

    // MARK: - Incremental

    func testIncrementalSyncAppliesUpdateAndDeleteAndReplacesToken() async throws {
        _ = try await bootstrapped()
        clock.now = Self.start.addingTimeInterval(Self.day)
        relay.serve(incrementalPath(token: "sample-token-1"), json: Self.page(
            hasMore: false,
            next: nil,
            token: "sample-token-2",
            mutations: [
                Self.mutation(sequence: 202, type: "ROW_DELETE", recordKey: "9003"),
                Self.mutation(sequence: 201, type: "ROW_UPDATE", recordKey: "9001",
                              data: Self.row(id: 9001, verse: "1:1", text: "sample text 1 updated"))
            ]
        ))

        _ = try await engine.sync(id: Self.id)

        let stored = try XCTUnwrap(storage.load(id: Self.id))
        XCTAssertEqual(stored.syncToken, "sample-token-2")
        XCTAssertEqual(stored.lastSyncedAt, Self.start.addingTimeInterval(Self.day))
        let verses = stored.versesByKey()
        XCTAssertEqual(verses["1:1"], "sample text 1 updated")
        XCTAssertEqual(verses["1:2"], "sample text 2 revised")
        XCTAssertNil(verses["1:3"])
        XCTAssertEqual(verses.count, 2)
        XCTAssertEqual(relay.requested.last, incrementalPath(token: "sample-token-1"))
    }

    func testTokenRejectionReBootstraps() async throws {
        _ = try await bootstrapped()
        let incremental = incrementalPath(token: "sample-token-1")
        relay.fail(incremental, with: RelayError.client(status: 410, code: "resync_required"))
        // Fresh public content for the re-bootstrap.
        let freshBootstrap = Self.page(
            hasMore: false,
            next: nil,
            token: "sample-token-fresh",
            mutations: [Self.mutation(sequence: 500, type: "RESOURCE_CREATE", snapshotURL: Self.snapshotPath)]
        )
        relay.serve(Self.bootstrapPath, json: freshBootstrap)
        relay.serve(Self.snapshotPath, json: Self.snapshot([
            Self.row(id: 9101, verse: "1:1", text: "sample text 10"),
            Self.row(id: 9102, verse: "1:2", text: "sample text 11")
        ]))

        let before = relay.requested.count
        _ = try await engine.sync(id: Self.id)

        XCTAssertEqual(Array(relay.requested.dropFirst(before)), [incremental, Self.bootstrapPath, Self.snapshotPath])
        let stored = try XCTUnwrap(storage.load(id: Self.id))
        XCTAssertEqual(stored.syncToken, "sample-token-fresh")
        XCTAssertEqual(stored.versesByKey(), ["1:1": "sample text 10", "1:2": "sample text 11"])
        XCTAssertEqual(stored.name, "Sample Translation")
    }

    // MARK: - Failures keep the last good copy

    func testFailedPageLeavesPreviousCopyIntact() async throws {
        let previous = try await bootstrapped()
        clock.now = Self.start.addingTimeInterval(8 * Self.day)
        relay.serve(incrementalPath(token: "sample-token-1"), json: Self.page(
            hasMore: true,
            next: "/api/v4/resources/sync?cursor=sample-cursor-offline&per_page=100&resources=translations%3A20",
            token: nil,
            mutations: [Self.mutation(sequence: 301, type: "ROW_DELETE", recordKey: "9001")]
        ))
        // The next page is not served: the fake answers as if offline.

        do {
            _ = try await engine.sync(id: Self.id)
            XCTFail("Expected the sync to fail")
        } catch {
            XCTAssertEqual(error as? RelayError, .transport)
        }

        let stored = try XCTUnwrap(storage.load(id: Self.id))
        XCTAssertEqual(stored, previous)
        XCTAssertEqual(stored.syncToken, "sample-token-1")
        XCTAssertEqual(stored.versesByKey()["1:1"], "sample text 1")
    }

    func testFailedReBootstrapLeavesPreviousCopyIntact() async throws {
        let previous = try await bootstrapped()
        relay.fail(incrementalPath(token: "sample-token-1"), with: RelayError.client(status: 410, code: "resync_required"))
        relay.serve(Self.bootstrapPath, json: Self.page(
            hasMore: false,
            next: nil,
            token: "sample-token-never-stored",
            mutations: [Self.mutation(sequence: 600, type: "RESOURCE_CREATE", snapshotURL: "/api/v4/resources/snapshots/translations/20?sample=offline")]
        ))

        do {
            _ = try await engine.sync(id: Self.id)
            XCTFail("Expected the sync to fail")
        } catch {
            XCTAssertEqual(error as? RelayError, .transport)
        }
        XCTAssertEqual(storage.load(id: Self.id), previous)
    }

    func testFailedFirstDownloadWritesNothing() async throws {
        relay.fail(Self.bootstrapPath, with: RelayError.server(status: 503))
        do {
            _ = try await engine.download(info)
            XCTFail("Expected the download to fail")
        } catch {
            XCTAssertEqual(error as? RelayError, .server(status: 503))
        }
        XCTAssertNil(storage.load(id: Self.id))
    }

    func testResourceDeleteRemovesTheLocalCopy() async throws {
        _ = try await bootstrapped()
        relay.serve(incrementalPath(token: "sample-token-1"), json: Self.page(
            hasMore: false,
            next: nil,
            token: "sample-token-3",
            mutations: [Self.mutation(sequence: 700, type: "RESOURCE_DELETE")]
        ))
        let outcome = try await engine.sync(id: Self.id)
        XCTAssertEqual(outcome, .removed(id: Self.id))
        XCTAssertNil(storage.load(id: Self.id))
    }

    // MARK: - Seven day rule

    func testStalenessAfterSevenDaysWithInjectedClock() async throws {
        _ = try await bootstrapped()
        let requestsAfterBootstrap = relay.requested.count

        clock.now = Self.start.addingTimeInterval(6 * Self.day)
        var stale = await engine.needsRefresh(id: Self.id)
        XCTAssertFalse(stale)
        let notDue = try await engine.refreshIfNeeded(id: Self.id)
        XCTAssertNil(notDue)
        XCTAssertEqual(relay.requested.count, requestsAfterBootstrap, "No request while the copy is fresh")

        clock.now = Self.start.addingTimeInterval(7 * Self.day)
        stale = await engine.needsRefresh(id: Self.id)
        XCTAssertFalse(stale, "Exactly seven days is still fresh")

        clock.now = Self.start.addingTimeInterval(7 * Self.day + 1)
        stale = await engine.needsRefresh(id: Self.id)
        XCTAssertTrue(stale)
        let staleIDs = await engine.staleIDs()
        XCTAssertEqual(staleIDs, [Self.id])

        relay.serve(incrementalPath(token: "sample-token-1"), json: Self.page(hasMore: false, next: nil, token: "sample-token-4", mutations: []))
        let refreshed = try await engine.refreshIfNeeded(id: Self.id)
        XCTAssertNotNil(refreshed)
        let after = await engine.needsRefresh(id: Self.id)
        XCTAssertFalse(after)
        XCTAssertEqual(storage.load(id: Self.id)?.lastSyncedAt, Self.start.addingTimeInterval(7 * Self.day + 1))
    }

    func testSummaryStalenessRule() {
        let summary = TranslationSummary(id: 1, name: "Sample", authorName: nil, languageName: "english", lastSyncedAt: Self.start)
        XCTAssertFalse(summary.needsRefresh(now: Self.start.addingTimeInterval(7 * Self.day)))
        XCTAssertTrue(summary.needsRefresh(now: Self.start.addingTimeInterval(7 * Self.day + 1)))
    }

    // MARK: - Paths and decoding

    func testIncrementalPathEncodesTheToken() {
        XCTAssertEqual(
            TranslationSyncEngine.incrementalPath(id: 20, token: "sample+token/1="),
            "/api/v4/resources/sync?resources=translations:20&sync_token=sample%2Btoken%2F1%3D&per_page=100"
        )
        XCTAssertEqual(TranslationSyncEngine.bootstrapPath(id: 20), Self.bootstrapPath)
    }

    func testMutationDecodingMatchesDocumentedFields() throws {
        let json = Self.page(hasMore: false, next: nil, token: "sample-token", mutations: [
            Self.mutation(sequence: 1, type: "ROW_UPDATE", recordKey: "9", data: Self.row(id: 9, verse: "2:3", text: "sample text 9")),
            Self.mutation(sequence: 2, type: "RESOURCE_INVALIDATE", snapshotURL: Self.snapshotPath),
            Self.mutation(sequence: 3, type: "SOMETHING_NEW")
        ])
        let response = try RelayClient.makeDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        XCTAssertFalse(response.sync.hasMore)
        XCTAssertEqual(response.sync.nextSyncToken, "sample-token")
        XCTAssertNil(response.sync.nextPageUrl)
        XCTAssertEqual(response.sync.syncUntilSequence, 900)
        XCTAssertEqual(response.sync.mutations.count, 3)
        let first = response.sync.mutations[0]
        XCTAssertEqual(first.type, .rowUpdate)
        XCTAssertEqual(first.recordKey, "9")
        XCTAssertEqual(first.recordType, "translation")
        XCTAssertEqual(first.data, TranslationRecord(id: 9, verseKey: "2:3", text: "sample text 9"))
        XCTAssertEqual(response.sync.mutations[1].type, .resourceInvalidate)
        XCTAssertEqual(response.sync.mutations[1].snapshotUrl, Self.snapshotPath)
        XCTAssertEqual(response.sync.mutations[2].type, .unknown("SOMETHING_NEW"))
    }

    // MARK: - Footnotes

    func testFootnoteMarkupIsRemovedAndNothingElse() {
        XCTAssertEqual(
            TranslationText.removingFootnotes("sample text<sup foot_note=123>1</sup> more"),
            "sample text more"
        )
        XCTAssertEqual(
            TranslationText.removingFootnotes("a<sup foot_note=1>1</sup>, b<SUP foot_note=\"2\">2</SUP>."),
            "a, b."
        )
        XCTAssertEqual(
            TranslationText.removingFootnotes("sample<sup foot_note=3>line\nbreak</sup> end"),
            "sample end"
        )
    }

    func testTextWithoutFootnotesIsUnchanged() {
        for text in ["sample text 1", "  spaced  text  ", "a < b and <b>bold</b>", "open <sup foot_note=4>never closed", ""] {
            XCTAssertEqual(TranslationText.removingFootnotes(text), text)
        }
    }

    // MARK: - Suggestion, grouping, attribution

    func testSuggestionPrefersClearQuranThenSaheehNeverById() {
        let clear = TranslationInfo(id: 501, name: "The Clear Quran", authorName: "Sample A", languageName: "english")
        let saheeh = TranslationInfo(id: 502, name: "Saheeh International", authorName: "Sample B", languageName: "english")
        let other = TranslationInfo(id: 503, name: "Sample Other", authorName: nil, languageName: "english")
        let foreignClear = TranslationInfo(id: 504, name: "Clear Quran", authorName: nil, languageName: "french")

        XCTAssertEqual(TranslationText.suggestion(in: [other, saheeh, clear])?.id, 501)
        XCTAssertEqual(TranslationText.suggestion(in: [other, saheeh])?.id, 502)
        XCTAssertNil(TranslationText.suggestion(in: [other, foreignClear]))
        XCTAssertNil(TranslationText.suggestion(in: []))
    }

    func testGroupingPutsEnglishFirst() {
        let groups = TranslationText.groupedByLanguage([
            TranslationInfo(id: 1, name: "Sample Z", authorName: nil, languageName: "urdu"),
            TranslationInfo(id: 2, name: "Sample B", authorName: nil, languageName: "english"),
            TranslationInfo(id: 3, name: "Sample A", authorName: nil, languageName: "bosnian"),
            TranslationInfo(id: 4, name: "Sample A", authorName: nil, languageName: "english")
        ])
        XCTAssertEqual(groups.map(\.language), ["English", "Bosnian", "Urdu"])
        XCTAssertEqual(groups.first?.translations.map(\.id), [4, 2])
    }

    func testAttribution() {
        XCTAssertEqual(
            TranslationText.attribution(name: "Sample Name", authorName: "Sample Author"),
            "Translation: Sample Name by Sample Author. Provided by Quran Foundation."
        )
        XCTAssertEqual(
            TranslationText.attribution(name: "Sample Name", authorName: " "),
            "Translation: Sample Name. Provided by Quran Foundation."
        )
    }
}
