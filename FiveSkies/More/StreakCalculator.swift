import Foundation

/// Pure streak arithmetic over "yyyy-MM-dd" day keys, the same keys PrayedStore uses.
/// A key in the set means all five prayers were marked on that day.
struct StreakCalculator {
    let calendar: Calendar

    init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The same key format as `PrayedStore.dayKey(for:)`.
    func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Consecutive complete days ending today, or ending yesterday when today is not complete yet.
    func currentStreak(completedDays: Set<String>, today: Date) -> Int {
        var day = calendar.startOfDay(for: today)
        if !completedDays.contains(dayKey(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while completedDays.contains(dayKey(for: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The longest run of consecutive complete days anywhere in the history.
    func bestStreak(completedDays: Set<String>) -> Int {
        let dates = completedDays.compactMap { date(fromKey: $0) }.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for date in dates {
            if let previous,
               let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: date) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = date
        }
        return best
    }

    /// Noon on the day named by a "yyyy-MM-dd" key, or nil if the key is malformed.
    func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}
