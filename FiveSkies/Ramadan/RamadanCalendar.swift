import Foundation

/// One day in the Hijri calendar, used as a storage key.
struct HijriDay: Hashable {
    let year: Int
    let month: Int
    let day: Int

    /// "1448-09-01" style key.
    var key: String {
        String(format: "%04ld-%02ld-%02ld", year, month, day)
    }
}

/// The next 1 Ramadan after a given day.
struct UpcomingRamadan: Equatable {
    /// Start of the day of 1 Ramadan, in the calendar's time zone.
    let start: Date
    /// Whole days from the start of the given day to `start`.
    let daysAway: Int
    let hijriYear: Int
}

/// Pure Ramadan date logic on top of a Hijri calendar (Umm al-Qura in the app).
/// Takes the calendar and the date from the caller so it can be tested with fixed values.
struct RamadanCalendar {
    static let ramadanMonth = 9
    /// The fasting log always shows this many days.
    static let logDayCount = 30
    /// A Hijri year has 354 or 355 days, so the next 1 Ramadan is never further away than this.
    static let searchLimit = 400

    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// The Umm al-Qura calendar in `timeZone`.
    init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en")
        self.calendar = calendar
    }

    func hijriDay(for date: Date) -> HijriDay? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return HijriDay(year: year, month: month, day: day)
    }

    /// The day of Ramadan (1...30) on `date`, or nil outside Ramadan.
    func dayOfRamadan(on date: Date) -> Int? {
        guard let today = hijriDay(for: date), today.month == Self.ramadanMonth else { return nil }
        return today.day
    }

    func isRamadan(_ date: Date) -> Bool {
        dayOfRamadan(on: date) != nil
    }

    /// The first 1 Ramadan strictly after the day containing `date`, found by stepping
    /// forward one day at a time through the calendar.
    func nextRamadan(after date: Date) -> UpcomingRamadan? {
        let start = calendar.startOfDay(for: date)
        for step in 1...Self.searchLimit {
            guard let candidate = calendar.date(byAdding: .day, value: step, to: start) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: candidate)
            if parts.month == Self.ramadanMonth, parts.day == 1, let year = parts.year {
                return UpcomingRamadan(start: calendar.startOfDay(for: candidate), daysAway: step, hijriYear: year)
            }
        }
        return nil
    }

    /// The Hijri year of the Ramadan the fasting log shows: this one during Ramadan, otherwise the next.
    func logYear(for date: Date) -> Int? {
        guard let today = hijriDay(for: date) else { return nil }
        return today.month <= Self.ramadanMonth ? today.year : today.year + 1
    }

    /// The Hijri date in English, such as "16 Jumada I 1448 AH".
    func hijriDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en")
        formatter.dateFormat = "d MMMM y"
        return formatter.string(from: date) + " AH"
    }
}

/// Which of the two daily fasting times comes next.
enum RamadanMoment: Equatable {
    case suhoorEnds
    case iftar

    var title: String {
        switch self {
        case .suhoorEnds: return "Suhoor ends"
        case .iftar: return "Iftar"
        }
    }
}

struct RamadanTarget: Equatable {
    let moment: RamadanMoment
    let time: Date
}

/// Suhoor ends at Fajr and Iftar is at Maghrib. Pure helpers for the countdown.
enum RamadanTimes {
    /// The next of today's Fajr, today's Maghrib, or tomorrow's Fajr after `now`.
    static func next(after now: Date, in day: PrayerDay) -> RamadanTarget {
        if now < day.fajr {
            return RamadanTarget(moment: .suhoorEnds, time: day.fajr)
        }
        if now < day.maghrib {
            return RamadanTarget(moment: .iftar, time: day.maghrib)
        }
        return RamadanTarget(moment: .suhoorEnds, time: day.tomorrowFajr)
    }

    /// "1h 12m" style, rounded up to the next whole minute.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}
