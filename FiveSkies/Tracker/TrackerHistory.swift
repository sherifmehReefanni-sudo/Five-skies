import Foundation

/// How the tracker shows one day.
struct TrackerDayStatus: Equatable {
    enum Phase: Equatable {
        /// Before the first day the user ever tracked. Drawn blank, never as unmarked.
        case notStarted
        /// The first tracked day up to today. Today is always active so it can be marked.
        case active
        case future
    }

    let key: String
    let prayed: Set<Prayer>
    let isPaused: Bool
    let phase: Phase

    var count: Int { prayed.count }

    var isComplete: Bool { prayed.isSuperset(of: Set(Prayer.allCases)) }
}

/// A Gregorian month for the history grid.
struct TrackerMonth: Equatable {
    let start: Date
    /// Empty slots before day 1, from the locale's first weekday.
    let leadingBlanks: Int
    /// Each day of the month, at the start of the day.
    let dates: [Date]
}

/// What the Today chips show.
struct TrackerChipsSummary: Equatable {
    let markedToday: Int
    let streak: Int
    let isPausedToday: Bool
}

/// Pure tracker figures over the stored prayer marks and pauses.
/// Counting starts on the first day the user tracked; days before it are never counted.
struct TrackerHistory {
    let days: [String: Set<Prayer>]
    let pauses: [TrackerPause]
    let calculator: StreakCalculator
    let locale: Locale
    /// Earliest day key with any prayer marked.
    let firstTrackedKey: String?
    /// Day keys with all five prayers marked.
    let completeKeys: Set<String>

    init(days: [String: Set<Prayer>], pauses: [TrackerPause], calculator: StreakCalculator, locale: Locale = .current) {
        self.days = days
        self.pauses = pauses
        self.calculator = calculator
        self.locale = locale
        let everyPrayer = Set(Prayer.allCases)
        firstTrackedKey = days.compactMap { key, prayers in
            !prayers.isEmpty && calculator.date(fromKey: key) != nil ? key : nil
        }.min()
        completeKeys = Set(days.compactMap { key, prayers in
            prayers.isSuperset(of: everyPrayer) ? key : nil
        })
    }

    /// Reads prayer marks and pauses from `defaults`.
    static func load(
        defaults: UserDefaults = .standard,
        calculator: StreakCalculator = StreakCalculator(),
        locale: Locale = .current
    ) -> TrackerHistory {
        let store = PrayedStore(defaults: defaults, timeZone: calculator.calendar.timeZone)
        return TrackerHistory(
            days: store.allDays(),
            pauses: PauseStore(defaults: defaults).all(),
            calculator: calculator,
            locale: locale
        )
    }

    /// The streak calendar with the locale applied, so weeks start on the user's first weekday.
    var displayCalendar: Calendar {
        var calendar = calculator.calendar
        calendar.locale = locale
        return calendar
    }

    var hasTracked: Bool { firstTrackedKey != nil }

    // MARK: - Pauses

    func isPaused(_ key: String) -> Bool {
        pauses.contains { $0.covers(key) }
    }

    /// The pause covering `date`, if any.
    func activePause(on date: Date) -> TrackerPause? {
        let key = calculator.dayKey(for: date)
        return pauses.first { $0.covers(key) }
    }

    // MARK: - Days

    func status(for date: Date, today: Date) -> TrackerDayStatus {
        let key = calculator.dayKey(for: date)
        let todayKey = calculator.dayKey(for: today)
        let phase: TrackerDayStatus.Phase
        if key > todayKey {
            phase = .future
        } else if key == todayKey {
            phase = .active
        } else if let first = firstTrackedKey, key >= first {
            phase = .active
        } else {
            phase = .notStarted
        }
        return TrackerDayStatus(
            key: key,
            prayed: days[key] ?? [],
            isPaused: phase != .notStarted && isPaused(key),
            phase: phase
        )
    }

    /// The seven days of the calendar week containing `today`, first weekday from the locale.
    func week(containing today: Date) -> [Date] {
        let calendar = displayCalendar
        let day = calendar.startOfDay(for: today)
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The `count` days ending with today, oldest first.
    func lastDays(_ count: Int, endingOn today: Date) -> [Date] {
        let calendar = calculator.calendar
        let day = calendar.startOfDay(for: today)
        return (0..<max(0, count)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
    }

    // MARK: - Streaks and totals

    func currentStreak(today: Date) -> Int {
        calculator.currentStreak(completedDays: completeKeys, today: today, isPaused: { key in isPaused(key) })
    }

    func bestStreak() -> Int {
        calculator.bestStreak(completedDays: completeKeys, isPaused: { key in isPaused(key) })
    }

    /// How many times each prayer was marked, from the first tracked day on.
    func perPrayerTotals() -> [Prayer: Int] {
        var totals: [Prayer: Int] = [:]
        for prayer in Prayer.allCases {
            totals[prayer] = 0
        }
        for prayers in days.values {
            for prayer in prayers {
                totals[prayer, default: 0] += 1
            }
        }
        return totals
    }

    var markedPrayerCount: Int {
        days.values.reduce(0) { $0 + $1.count }
    }

    var fullDayCount: Int { completeKeys.count }

    func chipsSummary(today: Date) -> TrackerChipsSummary {
        TrackerChipsSummary(
            markedToday: (days[calculator.dayKey(for: today)] ?? []).count,
            streak: currentStreak(today: today),
            isPausedToday: activePause(on: today) != nil
        )
    }

    // MARK: - Months

    /// The start of the month containing `date`.
    func monthStart(containing date: Date) -> Date {
        let calendar = displayCalendar
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// Month starts from the first tracked month to the month containing `today`, oldest first.
    /// Before any tracking this is just the current month.
    func monthStarts(today: Date) -> [Date] {
        let calendar = displayCalendar
        let last = monthStart(containing: today)
        var first = last
        if let key = firstTrackedKey, let date = calculator.date(fromKey: key) {
            first = min(monthStart(containing: date), last)
        }
        var result: [Date] = []
        var month = first
        while month <= last, result.count < 1200 {
            result.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return result
    }

    func month(startingAt start: Date) -> TrackerMonth {
        let calendar = displayCalendar
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return TrackerMonth(start: start, leadingBlanks: leading, dates: dates)
    }

    /// Very short weekday symbols starting from the locale's first weekday.
    var weekdaySymbols: [String] {
        let calendar = displayCalendar
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }

    /// A date formatter in the tracker's calendar, time zone and locale.
    func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = displayCalendar
        formatter.timeZone = calculator.calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
