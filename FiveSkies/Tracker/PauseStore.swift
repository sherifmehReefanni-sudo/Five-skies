import Foundation

/// Why the user paused the tracker. Shown with kind, neutral wording.
enum PauseReason: String, Codable, CaseIterable, Identifiable {
    case travel
    case illness
    case monthlyBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .travel: return "Travel"
        case .illness: return "Illness"
        case .monthlyBreak: return "Monthly break"
        }
    }

    var symbol: String {
        switch self {
        case .travel: return "airplane"
        case .illness: return "cross.case"
        case .monthlyBreak: return "leaf"
        }
    }
}

/// A stretch of days the tracker holds: paused days neither break nor add to the streak.
/// Days are "yyyy-MM-dd" keys, the same as PrayedStore, so they compare as plain strings.
struct TrackerPause: Codable, Identifiable, Equatable {
    var id: UUID
    var reason: PauseReason
    var startKey: String
    /// The last paused day, inclusive. Nil while the pause is open ended.
    var endKey: String?

    init(id: UUID = UUID(), reason: PauseReason, startKey: String, endKey: String? = nil) {
        self.id = id
        self.reason = reason
        self.startKey = startKey
        self.endKey = endKey
    }

    func covers(_ key: String) -> Bool {
        guard key >= startKey else { return false }
        if let endKey {
            return key <= endKey
        }
        return true
    }
}

/// Stores tracker pauses in UserDefaults as a JSON array.
struct PauseStore {
    static let storageKey = "tracker.pauses"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Every pause, newest start first.
    func all() -> [TrackerPause] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([TrackerPause].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.startKey > $1.startKey }
    }

    /// Adds a pause, or replaces the stored pause with the same id.
    func save(_ pause: TrackerPause) {
        var list = all()
        list.removeAll { $0.id == pause.id }
        list.append(pause)
        write(list)
    }

    func remove(id: UUID) {
        write(all().filter { $0.id != id })
    }

    /// Ends a pause so `lastPausedKey` is its last day. A pause that would end before it
    /// starts (ended on its first day) is removed instead.
    func end(_ pause: TrackerPause, lastPausedKey: String) {
        if lastPausedKey < pause.startKey {
            remove(id: pause.id)
            return
        }
        var ended = pause
        ended.endKey = lastPausedKey
        save(ended)
    }

    private func write(_ list: [TrackerPause]) {
        if list.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
