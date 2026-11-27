import Foundation

/// One day column in the week strip or the 7 day trend.
struct TrackerDay: Identifiable {
    let date: Date
    let shortName: String
    let fullName: String
    let status: TrackerDayStatus
    let isToday: Bool

    var id: String { status.key }
    var key: String { status.key }
    var prayed: Set<Prayer> { status.prayed }
    var isFuture: Bool { status.phase == .future }

    /// Columns for `dates`, with day names in the user's locale.
    static func days(_ dates: [Date], today: Date, history: TrackerHistory) -> [TrackerDay] {
        let calendar = history.displayCalendar

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.locale = history.locale
        shortFormatter.dateFormat = "EEE"

        let fullFormatter = DateFormatter()
        fullFormatter.calendar = calendar
        fullFormatter.timeZone = calendar.timeZone
        fullFormatter.locale = history.locale
        fullFormatter.dateFormat = "EEEE"

        return dates.map { date in
            TrackerDay(
                date: date,
                shortName: shortFormatter.string(from: date),
                fullName: fullFormatter.string(from: date),
                status: history.status(for: date, today: today),
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }
    }
}
