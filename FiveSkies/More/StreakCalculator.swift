import Foundation

/// Pure streak arithmetic over "yyyy-MM-dd" day keys, the same keys PrayedStore uses.
/// A key in the set means all five prayers were marked on that day.
/// Paused days (from the tracker's pause mode) neither break nor add to a streak:
/// the streak bridges them. A complete day still counts even inside a pause.
struct StreakCalculator {
    /// Upper bound on days walked, so a stray key can never make a loop run away.
    static let maxDaysWalked = 40_000

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
        currentStreak(completedDays: completedDays, today: today, isPaused: { _ in false })
    }

    /// Consecutive complete days ending today (or yesterday while today is still open),
    /// stepping over paused days without counting them.
    func currentStreak(completedDays: Set<String>, today: Date, isPaused: (String) -> Bool) -> Int {
        guard let earliest = completedDays.compactMap({ date(fromKey: $0) }).min() else { return 0 }
        let floor = calendar.startOfDay(for: earliest)
        var day = calendar.startOfDay(for: today)
        if !completedDays.contains(dayKey(for: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        var steps = 0
        while day >= floor, steps < Self.maxDaysWalked {
            let key = dayKey(for: day)
            if completedDays.contains(key) {
                count += 1
            } else if !isPaused(key) {
                break
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            steps += 1
        }
        return count
    }

    /// The longest run of consecutive complete days anywhere in the history.
    func bestStreak(completedDays: Set<String>) -> Int {
        bestStreak(completedDays: completedDays, isPaused: { _ in false })
    }

    /// The longest run of complete days, where paused days between them keep the run going.
    func bestStreak(completedDays: Set<String>, isPaused: (String) -> Bool) -> Int {
        let dates = completedDays.compactMap { date(fromKey: $0) }.sorted()
        guard let first = dates.first, let last = dates.last else { return 0 }
        var best = 0
        var run = 0
        var day = first
        var steps = 0
        while day <= last, steps < Self.maxDaysWalked {
            let key = dayKey(for: day)
            if completedDays.contains(key) {
                run += 1
                best = max(best, run)
            } else if !isPaused(key) {
                run = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            steps += 1
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
