import Foundation

/// Saved ayahs, kept in mushaf order. Stored in UserDefaults as JSON of sura and ayah numbers only.
final class QuranBookmarksStore: ObservableObject {
    static let storageKey = "quranBookmarks"

    @Published private(set) var bookmarks: [AyahRef]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = Self.read(from: defaults)
    }

    func contains(_ ref: AyahRef) -> Bool {
        bookmarks.contains(ref)
    }

    func add(_ ref: AyahRef) {
        guard !bookmarks.contains(ref) else { return }
        bookmarks.append(ref)
        bookmarks.sort()
        save()
    }

    func remove(_ ref: AyahRef) {
        guard bookmarks.contains(ref) else { return }
        bookmarks.removeAll { $0 == ref }
        save()
    }

    func toggle(_ ref: AyahRef) {
        if contains(ref) {
            remove(ref)
        } else {
            add(ref)
        }
    }

    /// Removes the bookmarks at the given positions of `bookmarks`, as a list's swipe to delete does.
    func remove(atOffsets offsets: IndexSet) {
        let refs = offsets.compactMap { bookmarks.indices.contains($0) ? bookmarks[$0] : nil }
        guard !refs.isEmpty else { return }
        bookmarks.removeAll { refs.contains($0) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func read(from defaults: UserDefaults) -> [AyahRef] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AyahRef].self, from: data)
        else {
            return []
        }
        return Array(Set(decoded)).sorted()
    }
}

/// The last ayah the reader was on. Stored in UserDefaults as JSON of sura and ayah numbers only.
final class QuranLastReadStore: ObservableObject {
    static let storageKey = "quranLastRead"

    @Published private(set) var position: AyahRef?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AyahRef.self, from: data) {
            position = decoded
        } else {
            position = nil
        }
    }

    func update(_ ref: AyahRef) {
        guard ref != position else { return }
        position = ref
        guard let data = try? JSONEncoder().encode(ref) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        position = nil
        defaults.removeObject(forKey: Self.storageKey)
    }
}
