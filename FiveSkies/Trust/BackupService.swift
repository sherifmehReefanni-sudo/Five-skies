import Foundation

/// The small part of a key-value store the backup needs. The app uses iCloud key-value
/// storage; tests and screenshot mode use a store kept in memory.
protocol BackupKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data, forKey key: String)
    func removeValue(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

/// iCloud key-value storage. No account or sign-in inside the app: it rides on the
/// user's own iCloud. Without the iCloud entitlement it stays on the device and does not sync.
final class ICloudKeyValueStore: BackupKeyValueStore {
    private let store: NSUbiquitousKeyValueStore

    init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
    }

    func removeValue(forKey key: String) {
        store.removeObject(forKey: key)
    }

    @discardableResult func synchronize() -> Bool {
        store.synchronize()
    }
}

/// A store kept in memory, for screenshot mode and the unit test host.
final class InMemoryKeyValueStore: BackupKeyValueStore {
    private var values: [String: Data] = [:]

    init() {}

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func setData(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeValue(forKey key: String) {
        values[key] = nil
    }

    @discardableResult func synchronize() -> Bool {
        true
    }
}

/// One backup, stored as JSON under a single key. `payload` is a binary property list of the
/// included UserDefaults values, so numbers, true or false, text, lists and data keep their types.
struct BackupSnapshot: Codable, Equatable {
    let version: Int
    let createdAt: Date
    /// The keys inside `payload`, sorted, for a readable record.
    let keys: [String]
    let payload: Data
}

enum BackupError: LocalizedError, Equatable {
    case nothingToRestore
    case unreadable
    case newerVersion
    case tooLarge
    case unavailable

    var errorDescription: String? {
        switch self {
        case .nothingToRestore:
            return "There is no backup yet."
        case .unreadable:
            return "That backup could not be read."
        case .newerVersion:
            return "That backup was made by a newer version of Five Skies. Update the app, then try again."
        case .tooLarge:
            return "The backup is too large for iCloud key-value storage."
        case .unavailable:
            return "iCloud backup is not available on this device right now."
        }
    }
}

/// Copies the app's own settings and progress into iCloud key-value storage and back.
/// Never includes secrets, the first name (device only), caches, or anything from
/// Quran Foundation content sync.
final class BackupService {
    static let cloudKey = "fiveSkies.backup"
    static let currentVersion = 1
    /// iCloud key-value storage allows 1 MB in total; keep well under it.
    static let maxBytes = 900_000

    /// Exact keys included in the backup.
    static let includedKeys: Set<String> = [
        PrayedStore.storageKey,              // "prayedByDay"
        PauseStore.storageKey,               // "tracker.pauses"
        FastingLogStore.ramadanKey,          // "ramadan.fastedDays"
        FastingLogStore.voluntaryKey,        // "ramadan.voluntaryFasts"
        FastingLogStore.taraweehKey,         // "ramadan.taraweehNights"
        MemorizeProgressStore.storageKey,    // "memorizeProgress"
        QuranBookmarksStore.storageKey,      // "quranBookmarks"
        QuranLastReadStore.storageKey,       // "quranLastRead"
        SurahReaderView.textSizeKey,         // "quranArabicTextSize"
        SkyTheme.storageKey                  // "appearance.skyTheme"
    ]

    /// Key prefixes included in the backup: settings, tasbih, Ramadan, tracker, and the
    /// goals, dhikr and alerts keys other features add.
    static let includedPrefixes: [String] = [
        "settings.",
        "tasbih.",
        "ramadan.",
        "tracker.",
        "goals.",
        "dhikr.",
        "alerts."
    ]

    static func isIncluded(_ key: String) -> Bool {
        includedKeys.contains(key) || includedPrefixes.contains { key.hasPrefix($0) }
    }

    private let defaults: UserDefaults
    private let store: BackupKeyValueStore
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        store: BackupKeyValueStore,
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.store = store
        self.now = now
    }

    /// iCloud in the app; a store in memory in screenshot mode and the unit test host,
    /// so neither touches iCloud.
    static func live() -> BackupService {
        let launch = LaunchOptions()
        if launch.fixedPhase != nil || launch.isUnitTestHost {
            return BackupService(store: InMemoryKeyValueStore())
        }
        return BackupService(store: ICloudKeyValueStore())
    }

    // MARK: - Snapshot

    func makeSnapshot() throws -> BackupSnapshot {
        var values: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where Self.isIncluded(key) {
            values[key] = value
        }
        let payload: Data
        do {
            payload = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        } catch {
            throw BackupError.unreadable
        }
        return BackupSnapshot(
            version: Self.currentVersion,
            createdAt: now(),
            keys: values.keys.sorted(),
            payload: payload
        )
    }

    static func encode(_ snapshot: BackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> BackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(BackupSnapshot.self, from: data)
        } catch {
            throw BackupError.unreadable
        }
    }

    // MARK: - Back up and restore

    /// The backup currently in the store, if any and if readable.
    func latestSnapshot() -> BackupSnapshot? {
        guard let data = store.data(forKey: Self.cloudKey) else { return nil }
        return try? Self.decode(data)
    }

    /// Writes a fresh backup and returns its date.
    @discardableResult
    func backUp() throws -> Date {
        let snapshot = try makeSnapshot()
        let data = try Self.encode(snapshot)
        guard data.count <= Self.maxBytes else { throw BackupError.tooLarge }
        store.setData(data, forKey: Self.cloudKey)
        store.synchronize()
        guard store.data(forKey: Self.cloudKey) != nil else { throw BackupError.unavailable }
        return snapshot.createdAt
    }

    /// Writes the backed up values into UserDefaults and returns how many keys were restored.
    /// Keys not in the backup are left as they are. Keys outside the included list are ignored.
    @discardableResult
    func restore() throws -> Int {
        store.synchronize()
        guard let data = store.data(forKey: Self.cloudKey) else { throw BackupError.nothingToRestore }
        let snapshot = try Self.decode(data)
        guard snapshot.version <= Self.currentVersion else { throw BackupError.newerVersion }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: snapshot.payload, options: [], format: nil)
        } catch {
            throw BackupError.unreadable
        }
        guard let values = object as? [String: Any] else { throw BackupError.unreadable }
        var count = 0
        for (key, value) in values where Self.isIncluded(key) {
            defaults.set(value, forKey: key)
            count += 1
        }
        return count
    }
}
