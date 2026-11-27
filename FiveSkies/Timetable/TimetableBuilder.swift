import Foundation

/// Whether the timetable shows one month or a whole year.
enum TimetableScope: String, CaseIterable, Identifiable, Sendable {
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}

/// The Gregorian month (1 to 12) and year the timetable is for.
/// In year scope only `year` is used.
struct TimetableSelection: Equatable, Sendable {
    var year: Int
    var month: Int

    /// Moves by `value` months or years, depending on `scope`.
    func stepped(by value: Int, scope: TimetableScope) -> TimetableSelection {
        switch scope {
        case .year:
            return TimetableSelection(year: year + value, month: month)
        case .month:
            let index = year * 12 + (month - 1) + value
            let newYear = index >= 0 ? index / 12 : (index - 11) / 12
            return TimetableSelection(year: newYear, month: index - newYear * 12 + 1)
        }
    }
}

/// One day of the timetable. Times are instants; format them in the place's time zone.
struct TimetableRow: Equatable, Identifiable, Sendable {
    /// Noon of the day in the place's time zone.
    let date: Date
    let gregorianDay: Int
    /// Short weekday name in the user's locale, such as "Mon".
    let weekdayName: String
    /// Umm al-Qura day of the month after the user's adjustment.
    let hijriDay: Int
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date

    var id: Date { date }

    /// Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha, in column order.
    var times: [Date] {
        [fajr, sunrise, dhuhr, asr, maghrib, isha]
    }
}

/// One Gregorian month of rows with its headings.
struct TimetableMonth: Equatable, Identifiable, Sendable {
    let year: Int
    let month: Int
    /// Such as "December 2026", in the user's locale.
    let title: String
    /// The Hijri months the rows cover, such as "Jumada II to Rajab 1448 AH".
    let hijriTitle: String
    let rows: [TimetableRow]

    var id: Int { year * 100 + month }
}

/// Builds timetable rows from the prayer times service. Pure: no UI, no stored state.
struct TimetableBuilder {
    let place: Place
    let service: PrayerTimesService
    let hijriAdjustment: Int
    let locale: Locale

    /// Column titles shared by the screen and the PDF.
    static let columnTitles = ["Date", "Hijri", "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]

    init(place: Place, service: PrayerTimesService, hijriAdjustment: Int, locale: Locale = .current) {
        self.place = place
        self.service = service
        self.hijriAdjustment = hijriAdjustment
        self.locale = locale
    }

    /// "Makkah (default)" for the fallback, else "Your location (40.71, -74.01)".
    static func placeLabel(for place: Place) -> String {
        if place.isFallback {
            return "Makkah (default)"
        }
        let latitude = String(format: "%.2f", place.coordinate.latitude)
        let longitude = String(format: "%.2f", place.coordinate.longitude)
        return "Your location (\(latitude), \(longitude))"
    }

    /// The months shown for a selection: one month, or all twelve of the year.
    func months(for selection: TimetableSelection, scope: TimetableScope) -> [TimetableMonth] {
        switch scope {
        case .month:
            return [month(year: selection.year, month: selection.month)]
        case .year:
            return year(selection.year)
        }
    }

    /// The twelve months of `year`.
    func year(_ year: Int) -> [TimetableMonth] {
        (1...12).map { month(year: year, month: $0) }
    }

    /// Every day of the Gregorian month in the place's time zone.
    /// A day whose times cannot be calculated is left out.
    func month(year: Int, month: Int) -> TimetableMonth {
        let gregorian = gregorianCalendar
        let hijri = hijriCalendar
        let weekdayFormatter = Self.formatter(calendar: gregorian, locale: locale, template: "EEE")

        var rows: [TimetableRow] = []
        if let first = gregorian.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) {
            let dayCount = gregorian.range(of: .day, in: .month, for: first)?.count ?? 0
            for offset in 0..<dayCount {
                let day = offset + 1
                guard
                    let date = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                    let times = service.prayerDay(for: place, on: date)
                else { continue }
                let shifted = gregorian.date(byAdding: .day, value: hijriAdjustment, to: date) ?? date
                rows.append(TimetableRow(
                    date: date,
                    gregorianDay: day,
                    weekdayName: weekdayFormatter.string(from: date),
                    hijriDay: hijri.component(.day, from: shifted),
                    fajr: times.fajr,
                    sunrise: times.sunrise,
                    dhuhr: times.dhuhr,
                    asr: times.asr,
                    maghrib: times.maghrib,
                    isha: times.isha
                ))
            }
        }

        return TimetableMonth(
            year: year,
            month: month,
            title: Self.monthTitle(for: TimetableSelection(year: year, month: month), calendar: gregorian, locale: locale),
            hijriTitle: hijriTitle(for: rows, gregorian: gregorian, hijri: hijri),
            rows: rows
        )
    }

    /// "December 2026" in `locale`.
    static func monthTitle(for selection: TimetableSelection, calendar: Calendar, locale: Locale) -> String {
        let date = calendar.date(from: DateComponents(year: selection.year, month: selection.month, day: 15, hour: 12)) ?? Date()
        return formatter(calendar: calendar, locale: locale, template: "MMMM y").string(from: date)
    }

    private var gregorianCalendar: Calendar {
        var calendar = place.calendar
        calendar.locale = locale
        return calendar
    }

    private var hijriCalendar: Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = place.timeZone
        calendar.locale = Locale(identifier: "en")
        return calendar
    }

    private func hijriTitle(for rows: [TimetableRow], gregorian: Calendar, hijri: Calendar) -> String {
        guard let first = rows.first, let last = rows.last else { return "" }
        let start = gregorian.date(byAdding: .day, value: hijriAdjustment, to: first.date) ?? first.date
        let end = gregorian.date(byAdding: .day, value: hijriAdjustment, to: last.date) ?? last.date
        let english = Locale(identifier: "en")
        let monthYear = Self.formatter(calendar: hijri, locale: english, format: "MMMM y")
        let monthOnly = Self.formatter(calendar: hijri, locale: english, format: "MMMM")
        let startParts = hijri.dateComponents([.year, .month], from: start)
        let endParts = hijri.dateComponents([.year, .month], from: end)
        if startParts == endParts {
            return monthYear.string(from: start) + " AH"
        }
        let startText = startParts.year == endParts.year ? monthOnly.string(from: start) : monthYear.string(from: start)
        return "\(startText) to \(monthYear.string(from: end)) AH"
    }

    private static func formatter(calendar: Calendar, locale: Locale, template: String) -> DateFormatter {
        // Locale first: setting it afterwards can reset the calendar to the locale's own.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static func formatter(calendar: Calendar, locale: Locale, format: String) -> DateFormatter {
        // Locale first: setting it afterwards can reset the calendar to the locale's own.
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}

/// Formats prayer times in the place's time zone, 12 or 24 hour as the locale prefers.
struct TimetableTimeFormat {
    let usesTwelveHourClock: Bool
    private let formatter: DateFormatter

    /// `includesPeriod` adds "AM" or "PM" on 12 hour clocks; the narrow screen table leaves it out.
    init(timeZone: TimeZone, locale: Locale = .current, includesPeriod: Bool) {
        let hourPattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        usesTwelveHourClock = hourPattern.contains("a")
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if usesTwelveHourClock {
            formatter.dateFormat = includesPeriod ? "h:mm a" : "h:mm"
        } else {
            formatter.dateFormat = "HH:mm"
        }
        self.formatter = formatter
    }

    func string(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
