import Foundation

/// The kinds of personal goal a user can start from a template.
/// Every goal is a count toward a target. None is a streak, and gaps never reset anything.
enum GoalKind: String, Codable, CaseIterable, Identifiable {
    case fajrThisMonth
    case allFiveDays
    case nightPrayer
    case dhikrToday
    case dhikrWeek
    case custom

    var id: String { rawValue }

    /// The name of the template in the goal picker.
    var templateTitle: String {
        switch self {
        case .fajrThisMonth: return "Fajr this month"
        case .allFiveDays: return "All five prayers on a number of days"
        case .nightPrayer: return "Night prayer on a number of nights"
        case .dhikrToday: return "Dhikr today"
        case .dhikrWeek: return "Dhikr this week"
        case .custom: return "Your own goal"
        }
    }

    /// One line under the template and on the goal card.
    var detail: String {
        switch self {
        case .fajrThisMonth: return "Counts days you mark Fajr. Starts fresh each month."
        case .allFiveDays: return "No deadline. The days do not need to be in a row."
        case .nightPrayer: return "No deadline. Log each night you pray."
        case .dhikrToday: return "Counts your Tasbih taps. Starts fresh each day."
        case .dhikrWeek: return "Counts your Tasbih taps. Starts fresh each week."
        case .custom: return "Name it and count up at your own pace."
        }
    }

    var symbol: String {
        switch self {
        case .fajrThisMonth: return "sunrise"
        case .allFiveDays: return "checkmark.circle"
        case .nightPrayer: return "moon.stars"
        case .dhikrToday, .dhikrWeek: return "hand.tap"
        case .custom: return "star"
        }
    }

    var defaultTarget: Int {
        switch self {
        case .fajrThisMonth: return 9
        case .allFiveDays: return 40
        case .nightPrayer: return 40
        case .dhikrToday: return 100
        case .dhikrWeek: return 700
        case .custom: return 10
        }
    }

    var targetRange: ClosedRange<Int> {
        switch self {
        case .fajrThisMonth: return 1...31
        case .allFiveDays, .nightPrayer: return 1...365
        case .dhikrToday: return 10...10_000
        case .dhikrWeek: return 50...50_000
        case .custom: return 1...1_000
        }
    }

    var targetStep: Int {
        switch self {
        case .fajrThisMonth, .allFiveDays, .nightPrayer, .custom: return 1
        case .dhikrToday: return 10
        case .dhikrWeek: return 50
        }
    }

    /// Goals the user logs by hand rather than from the tracker or the Tasbih.
    var isManual: Bool {
        self == .nightPrayer || self == .custom
    }
}

/// One personal goal, stored on the device.
struct PersonalGoal: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: GoalKind
    /// Only used by custom goals.
    var name: String
    var target: Int
    /// The day the goal was made, "yyyy-MM-dd". Goals with no deadline count from this day.
    var startKey: String
    /// Night keys logged for a night prayer goal.
    var loggedKeys: [String]
    /// The count of a custom goal.
    var manualCount: Int
    /// The period whose completion was already celebrated, so it only happens once.
    var celebratedPeriod: String?

    init(
        id: UUID = UUID(),
        kind: GoalKind,
        name: String = "",
        target: Int,
        startKey: String,
        loggedKeys: [String] = [],
        manualCount: Int = 0,
        celebratedPeriod: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.target = min(max(target, kind.targetRange.lowerBound), kind.targetRange.upperBound)
        self.startKey = startKey
        self.loggedKeys = loggedKeys
        self.manualCount = max(0, manualCount)
        self.celebratedPeriod = celebratedPeriod
    }

    /// The goal as a short sentence, as in "All five prayers on 40 days".
    var title: String {
        switch kind {
        case .fajrThisMonth: return "Fajr, \(target) times this month"
        case .allFiveDays: return target == 1 ? "All five prayers on 1 day" : "All five prayers on \(target) days"
        case .nightPrayer: return target == 1 ? "Night prayer on 1 night" : "Night prayer on \(target) nights"
        case .dhikrToday: return "Dhikr \(target) times today"
        case .dhikrWeek: return "Dhikr \(target) times this week"
        case .custom:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "My goal" : trimmed
        }
    }
}

/// How far a goal has come: a count toward a target, nothing else.
struct GoalProgress: Equatable {
    let count: Int
    let target: Int

    init(count: Int, target: Int) {
        self.count = max(0, count)
        self.target = max(0, target)
    }

    /// From 0 to 1, capped at 1.
    var fraction: Double {
        target > 0 ? min(Double(count) / Double(target), 1) : 0
    }

    var isComplete: Bool {
        target > 0 && count >= target
    }

    /// "3 of 9".
    var text: String {
        "\(count) of \(target)"
    }
}

/// Daily dhikr totals across every phrase, keyed by local day "yyyy-MM-dd".
struct DhikrTotals: Equatable {
    var byDay: [String: Int]

    init(byDay: [String: Int] = [:]) {
        self.byDay = byDay
    }

    func total(on key: String) -> Int {
        byDay[key] ?? 0
    }

    func sum(of keys: [String]) -> Int {
        keys.reduce(0) { $0 + total(on: $1) }
    }

    mutating func add(_ amount: Int, on key: String) {
        guard amount > 0 else { return }
        byDay[key, default: 0] += amount
    }

    /// Drops days before `key`, so the stored dictionary stays small.
    mutating func prune(before key: String) {
        byDay = byDay.filter { $0.key >= key }
    }
}

/// Pure date and count arithmetic for goals, over the same day keys PrayedStore writes.
struct GoalCounter {
    /// Before this hour, a night prayer belongs to the night that began the evening before.
    static let nightEndsHour = 12

    let calendar: Calendar

    /// `firstWeekday` is 1 for Sunday, 2 for Monday; nil uses the user's locale.
    init(timeZone: TimeZone = .current, firstWeekday: Int? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = firstWeekday ?? Calendar.current.firstWeekday
        self.calendar = calendar
    }

    /// The same key format as `PrayedStore.dayKey(for:)`.
    func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "yyyy-MM" for the month containing `date`.
    func monthKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04ld-%02ld", parts.year ?? 0, parts.month ?? 0)
    }

    /// The night a prayer at `date` belongs to: the day key of the evening it began.
    /// A prayer at 3 in the morning counts for the night before.
    func nightKey(for date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        guard hour < Self.nightEndsHour,
              let previous = calendar.date(byAdding: .day, value: -1, to: date)
        else {
            return dayKey(for: date)
        }
        return dayKey(for: previous)
    }

    /// The seven days of the calendar week containing `date`, starting on `calendar.firstWeekday`.
    func week(containing date: Date) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func weekKeys(containing date: Date) -> [String] {
        week(containing: date).map(dayKey(for:))
    }

    /// The `count` days ending with `date`, oldest first.
    func lastDays(_ count: Int, endingOn date: Date) -> [Date] {
        let day = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
    }

    /// The period a goal's completion belongs to. A goal is celebrated once per period.
    func period(for goal: PersonalGoal, today: Date) -> String {
        switch goal.kind {
        case .fajrThisMonth: return monthKey(for: today)
        case .dhikrToday: return dayKey(for: today)
        case .dhikrWeek: return weekKeys(containing: today).first ?? dayKey(for: today)
        case .allFiveDays, .nightPrayer, .custom: return "all"
        }
    }

    /// How many times the goal has been met so far, in its current period.
    func count(
        for goal: PersonalGoal,
        today: Date,
        prayedDays: [String: Set<Prayer>],
        dhikr: DhikrTotals
    ) -> Int {
        let todayKey = dayKey(for: today)
        switch goal.kind {
        case .fajrThisMonth:
            let prefix = monthKey(for: today) + "-"
            return prayedDays.filter { day in
                day.key.hasPrefix(prefix) && day.key <= todayKey && day.value.contains(.fajr)
            }.count
        case .allFiveDays:
            let everyPrayer = Set(Prayer.allCases)
            return prayedDays.filter { day in
                day.key >= goal.startKey && day.key <= todayKey && day.value.isSuperset(of: everyPrayer)
            }.count
        case .nightPrayer:
            return Set(goal.loggedKeys).count
        case .dhikrToday:
            return dhikr.total(on: todayKey)
        case .dhikrWeek:
            return dhikr.sum(of: weekKeys(containing: today))
        case .custom:
            return goal.manualCount
        }
    }

    func progress(
        for goal: PersonalGoal,
        today: Date,
        prayedDays: [String: Set<Prayer>],
        dhikr: DhikrTotals
    ) -> GoalProgress {
        GoalProgress(
            count: count(for: goal, today: today, prayedDays: prayedDays, dhikr: dhikr),
            target: goal.target
        )
    }

    /// Whether the goal is complete in this period and has not been celebrated for it yet.
    func needsCelebration(_ goal: PersonalGoal, progress: GoalProgress, today: Date) -> Bool {
        progress.isComplete && goal.celebratedPeriod != period(for: goal, today: today)
    }
}
