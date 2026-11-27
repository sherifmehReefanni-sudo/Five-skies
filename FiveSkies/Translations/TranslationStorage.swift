import Foundation

/// One row kept on the device, by its Content Sync record key.
struct StoredTranslationRow: Codable, Equatable, Sendable {
    let verseKey: String
    /// The text exactly as Quran Foundation sent it.
    let text: String
}

/// The offline copy of one translation, kept only through Content Sync.
struct StoredTranslation: Codable, Equatable, Sendable {
    static let currentFormat = 1

    var format: Int = StoredTranslation.currentFormat
    let id: Int
    var name: String
    var authorName: String?
    var languageName: String?
    var lastSyncedAt: Date
    var syncToken: String?
    /// Rows by record key. The key is the record key from Content Sync, or the snapshot row id as a string.
    var rows: [String: StoredTranslationRow]

    /// `verse_key` ("2:255") to text, exactly as stored.
    func versesByKey() -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(rows.count)
        for row in rows.values {
            result[row.verseKey] = row.text
        }
        return result
    }

    var summary: TranslationSummary {
        TranslationSummary(id: id, name: name, authorName: authorName, languageName: languageName, lastSyncedAt: lastSyncedAt)
    }
}

/// What the UI needs to know about a downloaded translation, without its rows.
struct TranslationSummary: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let authorName: String?
    let languageName: String?
    let lastSyncedAt: Date

    /// True when the last successful sync is older than `maxAge` (7 days by default).
    func needsRefresh(now: Date, maxAge: TimeInterval = TranslationStorage.maxAge) -> Bool {
        TranslationStorage.needsRefresh(lastSyncedAt: lastSyncedAt, now: now, maxAge: maxAge)
    }
}

/// One JSON file per translation in Application Support/Translations,
/// written atomically and excluded from iCloud backup.
struct TranslationStorage: Sendable {
    /// Content Sync must run at least every 7 days when online.
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Translations, or nil if the system gives no such folder.
    static func defaultDirectory(fileManager: FileManager = .default) -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent("Translations", isDirectory: true)
    }

    static func needsRefresh(lastSyncedAt: Date, now: Date, maxAge: TimeInterval = TranslationStorage.maxAge) -> Bool {
        now.timeIntervalSince(lastSyncedAt) > maxAge
    }

    func fileURL(for id: Int) -> URL {
        directory.appendingPathComponent("translation-\(id).json", isDirectory: false)
    }

    func load(id: Int) -> StoredTranslation? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? Self.decoder().decode(StoredTranslation.self, from: data)
    }

    /// Every readable translation file, sorted by name.
    func loadAll() -> [StoredTranslation] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var result: [StoredTranslation] = []
        for name in names where name.hasPrefix("translation-") && name.hasSuffix(".json") {
            let idText = name.dropFirst("translation-".count).dropLast(".json".count)
            guard let id = Int(idText), let stored = load(id: id) else { continue }
            result.append(stored)
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ translation: StoredTranslation) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(directory)
        let data = try Self.encoder().encode(translation)
        let url = fileURL(for: translation.id)
        try data.write(to: url, options: [.atomic])
        // An atomic write replaces the file, so the flag is set again after every write.
        try Self.excludeFromBackup(url)
    }

    func remove(id: Int) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) == true
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
