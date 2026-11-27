import Foundation

/// Remembers which prayers were marked as prayed, per calendar day, in UserDefaults.
/// Stored as a JSON dictionary keyed by "yyyy-MM-dd".
struct PrayedStore {
    static let storageKey = "prayedByDay"

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, timeZone: TimeZone = .current) {
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func prayers(on date: Date) -> Set<Prayer> {
        load()[dayKey(for: date)] ?? []
    }

    func setPrayed(_ prayed: Bool, _ prayer: Prayer, on date: Date) {
        var all = load()
        let key = dayKey(for: date)
        var day = all[key] ?? []
        if prayed {
            day.insert(prayer)
        } else {
            day.remove(prayer)
        }
        all[key] = day.isEmpty ? nil : day
        save(all)
    }

    /// Every stored day, keyed by "yyyy-MM-dd". Days with nothing marked are not stored.
    func allDays() -> [String: Set<Prayer>] {
        load()
    }

    func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func load() -> [String: Set<Prayer>] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Set<Prayer>].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func save(_ all: [String: Set<Prayer>]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
