import Foundation

/// Formats prayer times for the small tiles: "5:34" plus a separate "AM" or "PM" in
/// 12-hour locales, or "17:34" with no period in 24-hour locales. Always in the place's time zone.
struct TileTimeFormat {
    let usesTwelveHourClock: Bool
    private let timeFormatter: DateFormatter
    private let periodFormatter: DateFormatter

    init(timeZone: TimeZone, locale: Locale = .current) {
        let hourPattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        usesTwelveHourClock = hourPattern.contains("a")

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateFormat = usesTwelveHourClock ? "h:mm" : "HH:mm"
        timeFormatter = time

        let period = DateFormatter()
        period.locale = locale
        period.timeZone = timeZone
        period.dateFormat = "a"
        periodFormatter = period
    }

    /// The hour and minutes, such as "5:34" or "17:34".
    func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "AM" or "PM" in the locale's words, or nil in 24-hour locales.
    func period(_ date: Date) -> String? {
        usesTwelveHourClock ? periodFormatter.string(from: date) : nil
    }
}
