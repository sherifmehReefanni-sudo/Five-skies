import Foundation

/// The five daily prayers. Also used to name the five skies on the Today screen.
enum Prayer: String, CaseIterable, Codable, Identifiable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fajr: return "Fajr"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
}

/// The next prayer and the moment it begins.
struct UpcomingPrayer: Equatable {
    let prayer: Prayer
    let time: Date
}

/// One day of prayer times, plus the following day's Fajr for rollover after Isha.
struct PrayerDay: Equatable {
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date
    let tomorrowFajr: Date

    /// The sunset sky starts this long before Maghrib.
    static let sunsetLeadTime: TimeInterval = 45 * 60

    func time(of prayer: Prayer) -> Date {
        switch prayer {
        case .fajr: return fajr
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }

    /// The first prayer that starts strictly after `date`, rolling over to tomorrow's Fajr after Isha.
    func nextPrayer(after date: Date) -> UpcomingPrayer {
        for prayer in Prayer.allCases where time(of: prayer) > date {
            return UpcomingPrayer(prayer: prayer, time: time(of: prayer))
        }
        return UpcomingPrayer(prayer: .fajr, time: tomorrowFajr)
    }

    /// Which of the five skies applies at `date`.
    func skyPhase(at date: Date) -> Prayer {
        if date < fajr { return .isha }
        if date < sunrise { return .fajr }
        if date < asr { return .dhuhr }
        if date < sunsetStart { return .asr }
        if date < isha { return .maghrib }
        return .isha
    }

    /// The time window in which `skyPhase(at:)` returns `phase` (Isha runs to tomorrow's Fajr).
    func window(for phase: Prayer) -> DateInterval {
        switch phase {
        case .fajr: return interval(fajr, sunrise)
        case .dhuhr: return interval(sunrise, asr)
        case .asr: return interval(asr, sunsetStart)
        case .maghrib: return interval(sunsetStart, isha)
        case .isha: return interval(isha, tomorrowFajr)
        }
    }

    /// The middle of the window for `phase`.
    func midpoint(of phase: Prayer) -> Date {
        let span = window(for: phase)
        return span.start.addingTimeInterval(span.duration / 2)
    }

    private var sunsetStart: Date {
        maghrib.addingTimeInterval(-Self.sunsetLeadTime)
    }

    private func interval(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}
