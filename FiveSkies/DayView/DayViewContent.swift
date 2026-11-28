import Foundation

/// One line on the Day view: a name with a single moment (such as sunrise) or a window.
struct DayTimeRow: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    /// nil for a single moment.
    let end: Date?
    /// The obligatory rakah count for a prayer row (`RakahCount`); nil for every other row.
    var rakahs: Int? = nil

    /// "2 rakahs" for a prayer row, nil otherwise.
    var rakahCaption: String? {
        RakahCount.caption(for: rakahs)
    }

    /// One readable sentence for VoiceOver, as in "Fajr, 5:34 AM to 6:52 AM".
    func spokenText(_ format: Date.FormatStyle) -> String {
        let startText = start.formatted(format)
        guard let end = end else {
            return "\(title), \(startText)"
        }
        return "\(title), \(startText) to \(end.formatted(format))"
    }

    /// Whether `date` falls inside this row's window. A single moment never contains it.
    func contains(_ date: Date) -> Bool {
        guard let end = end else { return false }
        return start <= date && date < end
    }
}

/// The rows and labels of the Day view, worked out from a `DaySchedule`. No astronomy here.
enum DayViewContent {
    /// Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha, each prayer with its window and rakah count.
    static func prayerRows(for schedule: DaySchedule, ishaEnd: IshaEndRule) -> [DayTimeRow] {
        var rows: [DayTimeRow] = []
        for prayer in Prayer.allCases {
            let window = schedule.window(of: prayer, ishaEnd: ishaEnd)
            rows.append(DayTimeRow(
                id: prayer.rawValue,
                title: prayer.displayName,
                start: window.start,
                end: window.end,
                rakahs: RakahCount.obligatory(for: prayer)
            ))
            if prayer == .fajr {
                rows.append(DayTimeRow(id: "sunrise", title: "Sunrise", start: schedule.day.sunrise, end: nil))
            }
        }
        return rows
    }

    /// The id of the row whose window holds `now`, or nil when none does.
    static func currentRowID(in rows: [DayTimeRow], at now: Date) -> String? {
        rows.first { $0.contains(now) }?.id
    }

    static func duhaRow(for schedule: DaySchedule) -> DayTimeRow {
        DayTimeRow(id: "duha", title: "Duha", start: schedule.duha.start, end: schedule.duha.end)
    }

    /// The three discouraged windows, labelled with `DiscouragedKind.displayName`.
    static func discouragedRows(for schedule: DaySchedule) -> [DayTimeRow] {
        schedule.discouraged.map { period in
            DayTimeRow(
                id: "discouraged-\(period.kind.rawValue)",
                title: period.kind.displayName,
                start: period.interval.start,
                end: period.interval.end
            )
        }
    }

    /// Middle of the night and the start of its last third, for the night after this day.
    static func nightRows(for schedule: DaySchedule) -> [DayTimeRow] {
        [
            DayTimeRow(id: "middleOfNight", title: "Middle of the night", start: schedule.middleOfNight, end: nil),
            DayTimeRow(id: "lastThird", title: "Last third of the night", start: schedule.lastThirdOfNight, end: nil)
        ]
    }

    static func fastingRows(for schedule: DaySchedule) -> [DayTimeRow] {
        [
            DayTimeRow(id: "suhurEnds", title: "Suhur ends", start: schedule.suhurEnds, end: nil),
            DayTimeRow(id: "iftar", title: "Iftar", start: schedule.iftar, end: nil)
        ]
    }

    /// "No change", "+1 day", "-2 days".
    static func hijriAdjustmentText(_ days: Int) -> String {
        if days == 0 { return "No change" }
        let sign = days > 0 ? "+" : "-"
        let count = abs(days)
        return "\(sign)\(count) \(count == 1 ? "day" : "days")"
    }
}

/// The Umm al-Qura date shown on the Day view, moved by the user's adjustment.
enum DayHijriDate {
    /// `date` moved by `adjustment` whole days in `calendar`.
    static func adjustedDate(_ date: Date, adjustment: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: adjustment, to: date) ?? date
    }

    /// Day, English month name and year, as in "16 Jumada II 1448 AH".
    static func text(for date: Date, adjustment: Int, timeZone: TimeZone) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let shifted = adjustedDate(date, adjustment: adjustment, calendar: gregorian)

        var hijri = Calendar(identifier: .islamicUmmAlQura)
        hijri.timeZone = timeZone
        let english = Locale(identifier: "en")
        hijri.locale = english

        let formatter = DateFormatter()
        formatter.calendar = hijri
        formatter.timeZone = timeZone
        formatter.locale = english
        formatter.dateFormat = "d MMMM y"
        return formatter.string(from: shifted) + " AH"
    }
}
