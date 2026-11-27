import Foundation

/// How well an ayah is known, as marked by the reader.
enum MemorizeStatus: String, Codable, Sendable {
    case known
    case learning
}

/// Splits the stored ayah text for the "First words" mode. Never changes the text itself.
enum MemorizeText {
    struct Split: Equatable {
        /// The stored text up to the end of the last shown word.
        let prefix: String
        /// Whether any words follow the prefix.
        let hasRemainder: Bool
    }

    /// The refs for an ayah range of one sura.
    static func refs(sura: Int, range: ClosedRange<Int>) -> [AyahRef] {
        range.map { AyahRef(sura: sura, aya: $0) }
    }

    /// The first `count` words, where words are separated by the ASCII space character.
    /// Works on Unicode scalars so the marks of the text are never touched.
    static func firstWords(_ text: String, count: Int = 2) -> Split {
        let scalars = text.unicodeScalars
        guard count > 0 else {
            return Split(prefix: "", hasRemainder: scalars.contains { $0 != " " })
        }
        var words = 0
        var inWord = false
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == " " {
                if inWord {
                    inWord = false
                    if words == count {
                        let prefix = String(scalars[scalars.startIndex..<index])
                        let rest = scalars[index...]
                        return Split(prefix: prefix, hasRemainder: rest.contains { $0 != " " })
                    }
                }
            } else if !inWord {
                inWord = true
                words += 1
            }
            index = scalars.index(after: index)
        }
        return Split(prefix: text, hasRemainder: false)
    }
}

/// Per ayah memorisation marks. Stored in UserDefaults as JSON of sura and ayah numbers only.
final class MemorizeProgressStore: ObservableObject {
    static let storageKey = "memorizeProgress"

    private struct Entry: Codable {
        let sura: Int
        let aya: Int
        let status: MemorizeStatus
    }

    @Published private(set) var statuses: [AyahRef: MemorizeStatus]

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = MemorizeProgressStore.storageKey) {
        self.defaults = defaults
        self.key = key
        statuses = Self.read(from: defaults, key: key)
    }

    func status(for ref: AyahRef) -> MemorizeStatus? {
        statuses[ref]
    }

    func mark(_ ref: AyahRef, as status: MemorizeStatus) {
        guard statuses[ref] != status else { return }
        statuses[ref] = status
        save()
    }

    func clear(_ ref: AyahRef) {
        guard statuses[ref] != nil else { return }
        statuses[ref] = nil
        save()
    }

    /// How many of `refs` are marked known.
    func knownCount(in refs: [AyahRef]) -> Int {
        refs.filter { statuses[$0] == .known }.count
    }

    private func save() {
        let entries = statuses
            .map { Entry(sura: $0.key.sura, aya: $0.key.aya, status: $0.value) }
            .sorted { AyahRef(sura: $0.sura, aya: $0.aya) < AyahRef(sura: $1.sura, aya: $1.aya) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func read(from defaults: UserDefaults, key: String) -> [AyahRef: MemorizeStatus] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return [:]
        }
        var result: [AyahRef: MemorizeStatus] = [:]
        for entry in entries {
            result[AyahRef(sura: entry.sura, aya: entry.aya)] = entry.status
        }
        return result
    }
}
