import Foundation

// Wire shapes of Quran Foundation Content Sync, as documented in the v4 reference
// ("Sync public content resources" and "Get content resource snapshot").
// Decoded with `convertFromSnakeCase`, so `next_page_url` becomes `nextPageUrl` and so on.

/// `GET /resources/sync` answer: `{ "sync": { ... } }`.
struct SyncResponse: Decodable, Sendable {
    let sync: SyncPage
}

struct SyncPage: Decodable, Sendable {
    let syncUntilSequence: Int64?
    let hasMore: Bool
    /// Relative path (starts with `/api/v4/`) of the next page while `hasMore` is true.
    let nextPageUrl: String?
    /// Set only on the final page.
    let nextSyncToken: String?
    let mutations: [SyncMutation]
}

/// The documented change types. Anything else is kept as `.unknown` and ignored.
enum SyncMutationType: Equatable, Sendable {
    case resourceCreate
    case resourceInvalidate
    case resourceDelete
    case resourceUpdate
    case rowCreate
    case rowUpdate
    case rowDelete
    case unknown(String)

    init(raw: String) {
        switch raw.uppercased() {
        case "RESOURCE_CREATE": self = .resourceCreate
        case "RESOURCE_INVALIDATE": self = .resourceInvalidate
        case "RESOURCE_DELETE": self = .resourceDelete
        case "RESOURCE_UPDATE": self = .resourceUpdate
        case "ROW_CREATE": self = .rowCreate
        case "ROW_UPDATE": self = .rowUpdate
        case "ROW_DELETE": self = .rowDelete
        default: self = .unknown(raw)
        }
    }
}

/// One entry of `sync.mutations`.
struct SyncMutation: Decodable, Sendable {
    let sequence: Int64
    let type: SyncMutationType
    let resourceGroup: String
    let resourceId: Int
    let recordType: String?
    let recordKey: String?
    /// The complete row for ROW_CREATE and ROW_UPDATE; null otherwise.
    let data: TranslationRecord?
    /// Relative path for RESOURCE_CREATE and RESOURCE_INVALIDATE.
    let snapshotUrl: String?

    private enum CodingKeys: String, CodingKey {
        case sequence, type, resourceGroup, resourceId, recordType, recordKey, data, snapshotUrl
    }

    init(
        sequence: Int64,
        type: SyncMutationType,
        resourceGroup: String,
        resourceId: Int,
        recordType: String? = nil,
        recordKey: String? = nil,
        data: TranslationRecord? = nil,
        snapshotUrl: String? = nil
    ) {
        self.sequence = sequence
        self.type = type
        self.resourceGroup = resourceGroup
        self.resourceId = resourceId
        self.recordType = recordType
        self.recordKey = recordKey
        self.data = data
        self.snapshotUrl = snapshotUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        type = SyncMutationType(raw: (try? container.decode(String.self, forKey: .type)) ?? "")
        resourceGroup = try container.decode(String.self, forKey: .resourceGroup)
        resourceId = try container.decode(Int.self, forKey: .resourceId)
        recordType = try? container.decodeIfPresent(String.self, forKey: .recordType)
        // The reference types record_key as a string; accept a number too, to be safe.
        if let key = try? container.decodeIfPresent(String.self, forKey: .recordKey) {
            recordKey = key
        } else if let number = try? container.decodeIfPresent(Int64.self, forKey: .recordKey) {
            recordKey = String(number)
        } else {
            recordKey = nil
        }
        // Row data of another shape (another group) must not fail the whole page.
        data = try? container.decodeIfPresent(TranslationRecord.self, forKey: .data)
        snapshotUrl = try? container.decodeIfPresent(String.self, forKey: .snapshotUrl)
    }
}

/// One translation row, as in the documented translation snapshot example:
/// `{ "id": ..., "verse_key": "26:153", "text": "..." }`.
struct TranslationRecord: Decodable, Equatable, Sendable {
    let id: Int64?
    let verseKey: String?
    let text: String?
}

/// `GET /resources/snapshots/{resource_group}/{id}` answer.
struct SnapshotResponse: Decodable, Sendable {
    let resourceGroup: String
    let resourceId: Int
    let resourceContentId: Int?
    let schemaVersion: Int?
    let syncSequence: Int64?
    let records: [TranslationRecord]
}

/// Content Sync error codes the engine reacts to.
enum ContentSyncErrorCode {
    /// The token or cursor cannot be used; bootstrap this filter again.
    static let resyncRequired = "resync_required"
    /// The token belongs to another resource filter; bootstrap this filter.
    static let tokenFilterMismatch = "token_filter_mismatch"
    /// The resource is not public; treat it as unavailable locally.
    static let snapshotNotFound = "snapshot_not_found"

    /// Whether a failed incremental sync means the stored token was rejected.
    static func isTokenRejection(_ error: Error) -> Bool {
        guard case RelayError.client(let status, let code) = error else { return false }
        if code == resyncRequired || code == tokenFilterMismatch {
            return true
        }
        // The reference lists resync_required under 410 Gone.
        return status == 410
    }

    static func isSnapshotNotFound(_ error: Error) -> Bool {
        guard case RelayError.client(_, let code) = error else { return false }
        return code == snapshotNotFound
    }
}
