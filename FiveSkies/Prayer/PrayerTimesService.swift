import Adhan
import Foundation

/// Calculates prayer times with the Adhan library. No astronomy is done here.
struct PrayerTimesService {
    var method: CalculationMethod
    var madhab: Madhab
    var timeZone: TimeZone

    init(
        method: CalculationMethod = .northAmerica,
        madhab: Madhab = .shafi,
        timeZone: TimeZone = .current
    ) {
        self.method = method
        self.madhab = madhab
        self.timeZone = timeZone
    }

    /// Prayer times for the calendar day containing `date` in `timeZone`, plus the next day's Fajr.
    func prayerDay(at coordinate: Coordinate, on date: Date) -> PrayerDay? {
        let calendar = localCalendar
        guard
            let nextDate = calendar.date(byAdding: .day, value: 1, to: date),
            let today = prayerTimes(at: coordinate, on: date, calendar: calendar),
            let tomorrow = prayerTimes(at: coordinate, on: nextDate, calendar: calendar)
        else {
            return nil
        }
        return PrayerDay(
            fajr: today.fajr,
            sunrise: today.sunrise,
            dhuhr: today.dhuhr,
            asr: today.asr,
            maghrib: today.maghrib,
            isha: today.isha,
            tomorrowFajr: tomorrow.fajr
        )
    }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func prayerTimes(at coordinate: Coordinate, on date: Date, calendar: Calendar) -> PrayerTimes? {
        var parameters = method.params
        parameters.madhab = madhab
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let coordinates = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return PrayerTimes(coordinates: coordinates, date: components, calculationParameters: parameters)
    }
}
