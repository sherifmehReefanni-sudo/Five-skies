import Foundation

/// One Gregorian day in the month grid, with its Umm al-Qura Hijri day number.
struct HijriDayCell: Equatable {
    let date: Date
    let gregorianDay: Int
    let hijriDay: Int
}

/// A grid position: a leading blank before the first day, or a day.
struct HijriGridSlot: Identifiable, Equatable {
    let id: Int
    let cell: HijriDayCell?
}

/// Pure date conversion for the Hijri calendar screen. Foundation only.
struct HijriCalendarMath {
    let gregorian: Calendar
    let hijri: Calendar

    private let hijriMonthFormatter: DateFormatter
    private let gregorianMonthFormatter: DateFormatter
    private let gregorianDayFormatter: DateFormatter

    init(timeZone: TimeZone = .current, locale: Locale = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        gregorian.locale = locale
        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = timeZone
        hijri.locale = Locale(identifier: "en")
        self.gregorian = gregorian
        self.hijri = hijri
        hijriMonthFormatter = HijriCalendarMath.formatter(calendar: hijri, locale: Locale(identifier: "en"), template: nil, format: "MMMM y")
        gregorianMonthFormatter = HijriCalendarMath.formatter(calendar: gregorian, locale: locale, template: "MMMM y", format: nil)
        gregorianDayFormatter = HijriCalendarMath.formatter(calendar: gregorian, locale: locale, template: "MMMM d", format: nil)
    }

    /// Year, month and day of `date` in the Umm al-Qura calendar.
    func hijriComponents(for date: Date) -> DateComponents {
        hijri.dateComponents([.year, .month, .day], from: date)
    }

    /// The first day of the Gregorian month `offset` months away from the month containing `date`.
    func monthStart(containing date: Date, offset: Int = 0) -> Date {
        let parts = gregorian.dateComponents([.year, .month], from: date)
        let start = gregorian.date(from: parts) ?? gregorian.startOfDay(for: date)
        return gregorian.date(byAdding: .month, value: offset, to: start) ?? start
    }

    /// Leading blanks plus one slot per day of the Gregorian month starting at `monthStart`.
    func slots(forMonthStarting monthStart: Date) -> [HijriGridSlot] {
        let dayCount = gregorian.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let weekday = gregorian.component(.weekday, from: monthStart)
        let leading = (weekday - gregorian.firstWeekday + 7) % 7

        var result: [HijriGridSlot] = []
        for index in 0..<leading {
            result.append(HijriGridSlot(id: index, cell: nil))
        }
        for offset in 0..<dayCount {
            guard let date = gregorian.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let cell = HijriDayCell(
                date: date,
                gregorianDay: gregorian.component(.day, from: date),
                hijriDay: hijri.component(.day, from: date)
            )
            result.append(HijriGridSlot(id: leading + offset, cell: cell))
        }
        return result
    }

    /// Very short weekday symbols starting from the locale's first weekday.
    var weekdaySymbols: [String] {
        let symbols = gregorian.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let first = max(0, min(6, gregorian.firstWeekday - 1))
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Hijri month name and year of `date`, in English.
    func hijriMonthTitle(for date: Date) -> String {
        hijriMonthFormatter.string(from: date)
    }

    /// Gregorian month and year in the user's locale.
    func gregorianMonthTitle(for date: Date) -> String {
        gregorianMonthFormatter.string(from: date)
    }

    /// Gregorian month and day, for accessibility labels.
    func gregorianDayTitle(for date: Date) -> String {
        gregorianDayFormatter.string(from: date)
    }

    private static func formatter(calendar: Calendar, locale: Locale, template: String?, format: String?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        if let format {
            formatter.dateFormat = format
        } else if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        }
        return formatter
    }
}
