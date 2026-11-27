import Adhan
import Foundation

/// Every school-dependent definition behind the extra times, in one file.
///
/// FABLE CHECKPOINT: these follow common practice. Schools differ on when the discouraged
/// windows begin and end, when Duha starts and when Isha ends. They must be signed off by a
/// scholar before the day view ships to anyone but Reef. Screens that show them carry
/// `DayDefinitions.commonPracticeNote`.
enum DayDefinitions {
    /// Minutes after sunrise during which voluntary prayer is discouraged (the sun rising).
    static let afterSunriseMinutes: Double = 15
    /// Minutes before Dhuhr during which voluntary prayer is discouraged (the sun at its height).
    static let beforeDhuhrMinutes: Double = 5
    /// Minutes before Maghrib during which voluntary prayer is discouraged (the sun setting).
    static let beforeMaghribMinutes: Double = 15

    /// Shown wherever these definitions are used.
    static let commonPracticeNote = "Common practice. Check with your local mosque."
}

/// The three times of day when voluntary prayer is discouraged.
enum DiscouragedKind: String, CaseIterable, Identifiable {
    case sunrise
    case zenith
    case sunset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sunrise: return "Sun rising"
        case .zenith: return "Sun at its height"
        case .sunset: return "Sun setting"
        }
    }
}

struct DiscouragedPeriod: Equatable, Identifiable {
    let kind: DiscouragedKind
    let interval: DateInterval

    var id: String { kind.rawValue }
}

/// One day's five prayers plus the extra times worked out from them.
/// The night times are for the night that follows this day (its Maghrib to the next Fajr),
/// from adhan-swift's SunnahTimes. No astronomy is done here.
struct DaySchedule: Equatable {
    let day: PrayerDay
    let duha: DateInterval
    let discouraged: [DiscouragedPeriod]
    let middleOfNight: Date
    let lastThirdOfNight: Date

    /// Suhur ends when Fajr begins.
    var suhurEnds: Date { day.fajr }
    /// Iftar is at Maghrib.
    var iftar: Date { day.maghrib }

    /// When `prayer` may be prayed: from its start to the next boundary.
    /// Fajr ends at sunrise; Dhuhr at Asr; Asr at Maghrib; Maghrib at Isha;
    /// Isha at the middle of the night or at the next Fajr, by `ishaEnd`.
    func window(of prayer: Prayer, ishaEnd: IshaEndRule) -> DateInterval {
        switch prayer {
        case .fajr: return Self.interval(day.fajr, day.sunrise)
        case .dhuhr: return Self.interval(day.dhuhr, day.asr)
        case .asr: return Self.interval(day.asr, day.maghrib)
        case .maghrib: return Self.interval(day.maghrib, day.isha)
        case .isha:
            switch ishaEnd {
            case .middleOfNight: return Self.interval(day.isha, middleOfNight)
            case .fajr: return Self.interval(day.isha, day.tomorrowFajr)
            }
        }
    }

    /// Builds the extras from a day and its night times using the offsets in `DayDefinitions`.
    static func make(day: PrayerDay, middleOfNight: Date, lastThirdOfNight: Date) -> DaySchedule {
        let afterSunrise = day.sunrise.addingTimeInterval(DayDefinitions.afterSunriseMinutes * 60)
        let beforeDhuhr = day.dhuhr.addingTimeInterval(-DayDefinitions.beforeDhuhrMinutes * 60)
        let beforeMaghrib = day.maghrib.addingTimeInterval(-DayDefinitions.beforeMaghribMinutes * 60)
        return DaySchedule(
            day: day,
            duha: interval(afterSunrise, beforeDhuhr),
            discouraged: [
                DiscouragedPeriod(kind: .sunrise, interval: interval(day.sunrise, afterSunrise)),
                DiscouragedPeriod(kind: .zenith, interval: interval(beforeDhuhr, day.dhuhr)),
                DiscouragedPeriod(kind: .sunset, interval: interval(beforeMaghrib, day.maghrib))
            ],
            middleOfNight: middleOfNight,
            lastThirdOfNight: lastThirdOfNight
        )
    }

    private static func interval(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: max(start, end))
    }
}

extension PrayerTimesService {
    /// The full schedule for the day containing `date` in the place's own time zone,
    /// or nil where the library cannot compute the times (for example near the poles).
    func daySchedule(for place: Place, on date: Date) -> DaySchedule? {
        let local = inTimeZone(place.timeZone)
        guard let day = local.prayerDay(at: place.coordinate, on: date),
              let times = local.prayerTimes(at: place.coordinate, on: date, calendar: local.localCalendar),
              let sunnah = SunnahTimes(from: times)
        else {
            return nil
        }
        return DaySchedule.make(
            day: day,
            middleOfNight: sunnah.middleOfTheNight,
            lastThirdOfNight: sunnah.lastThirdOfTheNight
        )
    }
}
