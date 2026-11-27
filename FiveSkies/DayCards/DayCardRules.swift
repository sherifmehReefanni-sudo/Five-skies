import Foundation

/// The kinds of day-aware reminder, in order of importance (most important first).
enum DayCardKind: String, CaseIterable {
    case eidAlFitr
    case eidAlAdha
    case dayOfArafah
    case ramadan
    case friday
    case whiteDay
    case monday
    case thursday
}

/// One plain reminder for Today: a one line title, an optional second line and an SF Symbol.
struct DayCard: Equatable, Identifiable {
    let kind: DayCardKind
    let title: String
    let subtitle: String?
    let symbol: String

    var id: String { kind.rawValue }
}

/// Pure rules for which day cards apply on a date. Foundation only.
/// The weekday comes from the Gregorian date in `timeZone`. The Hijri date is the
/// Umm al-Qura date of the Gregorian day moved by `hijriAdjustment` days, as everywhere
/// else a Hijri date is shown in the app.
struct DayCardRules {
    /// At most this many cards show at once.
    static let maxShown = 2

    static let shawwal = 10
    static let dhulHijjah = 12
    static let whiteDays = 13...15

    let gregorian: Calendar
    let hijri: Calendar
    /// Clamped to `AppSettings.hijriAdjustmentRange`.
    let hijriAdjustment: Int

    init(timeZone: TimeZone, hijriAdjustment: Int = 0) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = timeZone
        hijri.locale = Locale(identifier: "en")
        self.gregorian = gregorian
        self.hijri = hijri
        let range = AppSettings.hijriAdjustmentRange
        self.hijriAdjustment = min(max(hijriAdjustment, range.lowerBound), range.upperBound)
    }

    /// The adjusted Umm al-Qura date of the day containing `date`.
    func hijriDay(for date: Date) -> HijriDay? {
        let shifted = gregorian.date(byAdding: .day, value: hijriAdjustment, to: date) ?? date
        let parts = hijri.dateComponents([.year, .month, .day], from: shifted)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return HijriDay(year: year, month: month, day: day)
    }

    /// Every card that applies on `date`, most important first.
    func allCards(for date: Date) -> [DayCard] {
        let weekday = gregorian.component(.weekday, from: date)
        var result: [DayCard] = []

        if let day = hijriDay(for: date) {
            if day.month == Self.shawwal && day.day == 1 {
                result.append(Self.card(.eidAlFitr))
            }
            if day.month == Self.dhulHijjah && day.day == 10 {
                result.append(Self.card(.eidAlAdha))
            }
            if day.month == Self.dhulHijjah && day.day == 9 {
                result.append(Self.card(.dayOfArafah))
            }
            if day.month == RamadanCalendar.ramadanMonth {
                result.append(Self.ramadanCard(day: day.day))
            }
            if weekday == 6 {
                result.append(Self.card(.friday))
            }
            if Self.fastingNotesApply(on: day) {
                if Self.whiteDays.contains(day.day) {
                    result.append(Self.card(.whiteDay))
                }
                if weekday == 2 {
                    result.append(Self.card(.monday))
                }
                if weekday == 5 {
                    result.append(Self.card(.thursday))
                }
            }
        } else if weekday == 6 {
            result.append(Self.card(.friday))
        }
        return result
    }

    /// The cards to show on `date`: those not in `hiding` (card ids), at most `maxShown`.
    func cards(for date: Date, hiding: Set<String> = []) -> [DayCard] {
        Array(allCards(for: date).filter { !hiding.contains($0.id) }.prefix(Self.maxShown))
    }

    /// "2026-11-27" for the Gregorian day containing `date` in the rules' time zone.
    /// Dismissals are stored under this key.
    func dayKey(for date: Date) -> String {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The optional fasting notes (white days, Monday, Thursday) stay away from Ramadan,
    /// where they add nothing, and from the Eid days and the three days after Eid al-Adha.
    static func fastingNotesApply(on day: HijriDay) -> Bool {
        if day.month == RamadanCalendar.ramadanMonth { return false }
        if day.month == shawwal && day.day == 1 { return false }
        if day.month == dhulHijjah && (10...13).contains(day.day) { return false }
        return true
    }

    static func ramadanCard(day: Int) -> DayCard {
        DayCard(
            kind: .ramadan,
            title: "Ramadan, day \(day)",
            subtitle: day >= 21 ? "The last ten days" : nil,
            symbol: "moon.stars.fill"
        )
    }

    /// The fixed copy for every kind except Ramadan, which carries its day number.
    static func card(_ kind: DayCardKind) -> DayCard {
        switch kind {
        case .eidAlFitr:
            return DayCard(kind: kind, title: "Eid al-Fitr", subtitle: "A day of celebration", symbol: "sparkles")
        case .eidAlAdha:
            return DayCard(kind: kind, title: "Eid al-Adha", subtitle: "A day of celebration", symbol: "sparkles")
        case .dayOfArafah:
            return DayCard(kind: kind, title: "The Day of Arafah", subtitle: "The day before Eid al-Adha", symbol: "mountain.2.fill")
        case .ramadan:
            return ramadanCard(day: 1)
        case .friday:
            return DayCard(kind: kind, title: "It is Friday", subtitle: "The day of the Friday prayer", symbol: "sun.max.fill")
        case .whiteDay:
            return DayCard(kind: kind, title: "One of the white days", subtitle: "Some fast on days 13, 14 and 15", symbol: "moonphase.full.moon")
        case .monday:
            return DayCard(kind: kind, title: "It is Monday", subtitle: "Some choose to fast today", symbol: "calendar")
        case .thursday:
            return DayCard(kind: kind, title: "It is Thursday", subtitle: "Some choose to fast today", symbol: "calendar")
        }
    }
}

/// Which day cards were hidden for which day. Only the latest day is kept, so the
/// stored data never grows. Keys are prefixed with the feature name.
struct DayCardDismissals {
    static let dayKey = "dayCards.dismissed.day"
    static let idsKey = "dayCards.dismissed.ids"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Card ids hidden on the day with key `day`.
    func hidden(on day: String) -> Set<String> {
        guard defaults.string(forKey: Self.dayKey) == day else { return [] }
        return Set(defaults.stringArray(forKey: Self.idsKey) ?? [])
    }

    /// Hides the card with `id` for the rest of the day with key `day`.
    func hide(_ id: String, on day: String) {
        var ids = hidden(on: day)
        ids.insert(id)
        defaults.set(day, forKey: Self.dayKey)
        defaults.set(ids.sorted(), forKey: Self.idsKey)
    }
}

/// Testing hook read only by `DayCardsView`.
/// `-FSDayCardsDate yyyy-MM-dd` makes the cards evaluate that date instead of the clock.
struct DayCardsLaunchOptions {
    static let dateArgument = "-FSDayCardsDate"

    /// The raw "yyyy-MM-dd" text after the argument, or nil without it.
    let dateText: String?

    init(processInfo: ProcessInfo = .processInfo) {
        self.init(arguments: processInfo.arguments)
    }

    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: Self.dateArgument), arguments.indices.contains(index + 1) {
            dateText = arguments[index + 1]
        } else {
            dateText = nil
        }
    }

    /// Noon of the requested day in `timeZone`, or nil without a valid date.
    func date(in timeZone: TimeZone) -> Date? {
        dateText.flatMap { Self.parse($0, timeZone: timeZone) }
    }

    /// Noon of a strict "yyyy-MM-dd" day in `timeZone`, or nil for anything else.
    static func parse(_ text: String, timeZone: TimeZone) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month
        else {
            return nil
        }
        return date
    }
}
