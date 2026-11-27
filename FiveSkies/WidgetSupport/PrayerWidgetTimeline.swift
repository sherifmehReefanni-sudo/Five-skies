import Foundation

/// One prayer and its start time, for the rows and columns of the widgets.
struct PrayerWidgetRow: Equatable {
    let prayer: Prayer
    let time: Date
}

/// Everything a widget shows at one moment. Plain data, so the same views can be drawn in the
/// widget extension and in the app's debug widget gallery.
struct PrayerWidgetEntry: Equatable {
    /// When this entry takes effect.
    let date: Date
    /// Times are shown in this zone, the place's own.
    let timeZone: TimeZone
    /// True when the times are for the labelled Makkah fallback.
    let isFallback: Bool
    /// The five prayers of the day on show. After Isha this is the next day.
    let rows: [PrayerWidgetRow]
    let next: UpcomingPrayer
    /// When the prayer before `next` began, for the progress ring and bar.
    let previousStart: Date
    /// Which of the five skies applies at `date`.
    let phase: Prayer
    /// "Dhuhr", or "Morning" between sunrise and Dhuhr.
    let currentPeriodName: String

    /// How far `date` is from the previous prayer to the next, from 0 to 1.
    var progress: Double {
        let span = next.time.timeIntervalSince(previousStart)
        guard span > 0 else { return 0 }
        let done = date.timeIntervalSince(previousStart) / span
        return min(1, max(0, done))
    }

    /// Made up times for when no prayer times can be computed, so a widget always has something to draw.
    static func placeholder(at date: Date, timeZone: TimeZone) -> PrayerWidgetEntry {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let hours: [Prayer: Double] = [.fajr: 5, .dhuhr: 12, .asr: 15.5, .maghrib: 18, .isha: 19.5]
        let rows = Prayer.allCases.map { prayer in
            PrayerWidgetRow(prayer: prayer, time: start.addingTimeInterval((hours[prayer] ?? 12) * 3600))
        }
        let upcoming = rows.first { $0.time > date }
        let next = upcoming.map { UpcomingPrayer(prayer: $0.prayer, time: $0.time) }
            ?? UpcomingPrayer(prayer: .fajr, time: start.addingTimeInterval(29 * 3600))
        let previous = rows.last { $0.time <= date }?.time ?? start
        return PrayerWidgetEntry(
            date: date,
            timeZone: timeZone,
            isFallback: true,
            rows: rows,
            next: next,
            previousStart: previous,
            phase: .dhuhr,
            currentPeriodName: "Today"
        )
    }
}

/// Builds widget timelines from the shared prayer times service.
enum PrayerWidgetTimeline {
    /// Spacing of the extra entries that move the progress ring and bar along.
    static let progressStep: TimeInterval = 15 * 60

    /// Entries from `now` through tomorrow's Isha: one at `now`, one at every prayer time,
    /// at sunrise and at the start of the sunset sky (so the sky phase is right), and one at
    /// the next midnight in the place's time zone. Dates are strictly increasing.
    ///
    /// With `progressStep` set, entries are also added every step, and the timeline instead
    /// ends at the second prayer after `now`, so it stays short and is rebuilt often.
    static func entries(
        config: SharedPrayerConfig,
        now: Date,
        progressStep: TimeInterval? = nil,
        service: PrayerTimesService = PrayerTimesService()
    ) -> [PrayerWidgetEntry] {
        entryDates(config: config, now: now, progressStep: progressStep, service: service)
            .compactMap { entry(at: $0, config: config, service: service) }
    }

    /// The dates `entries` uses, strictly increasing and never before `now`.
    static func entryDates(
        config: SharedPrayerConfig,
        now: Date,
        progressStep: TimeInterval? = nil,
        service base: PrayerTimesService = PrayerTimesService()
    ) -> [Date] {
        let place = config.place
        let calendar = place.calendar
        let service = base.applying(method: config.calculationMethod, asrRule: config.asrRule)
        guard
            let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now),
            let today = service.prayerDay(for: place, on: now),
            let tomorrow = service.prayerDay(for: place, on: tomorrowDate)
        else {
            return [now]
        }

        var dates: [Date] = [now, calendar.startOfDay(for: tomorrowDate)]
        for day in [today, tomorrow] {
            dates += Prayer.allCases.map { day.time(of: $0) }
            dates.append(day.sunrise)
            dates.append(day.maghrib.addingTimeInterval(-PrayerDay.sunsetLeadTime))
        }

        var end = tomorrow.isha
        if let step = progressStep, step > 0 {
            let upcoming = (Prayer.allCases.map { today.time(of: $0) } + Prayer.allCases.map { tomorrow.time(of: $0) })
                .filter { $0 > now }
                .sorted()
            if upcoming.count > 1 {
                end = upcoming[1]
            }
            let first = (now.timeIntervalSinceReferenceDate / step).rounded(.down) * step + step
            var moment = Date(timeIntervalSinceReferenceDate: first)
            while moment < end {
                dates.append(moment)
                moment = moment.addingTimeInterval(step)
            }
        }

        return Array(Set(dates.filter { $0 >= now && $0 <= end })).sorted()
    }

    /// The entry in effect at `date`, or nil when prayer times cannot be computed there.
    static func entry(
        at date: Date,
        config: SharedPrayerConfig,
        service base: PrayerTimesService = PrayerTimesService()
    ) -> PrayerWidgetEntry? {
        let place = config.place
        let calendar = place.calendar
        let service = base.applying(method: config.calculationMethod, asrRule: config.asrRule)
        guard let today = service.prayerDay(for: place, on: date) else { return nil }

        var shown = today
        if date >= today.isha,
           let nextDate = calendar.date(byAdding: .day, value: 1, to: date),
           let tomorrow = service.prayerDay(for: place, on: nextDate) {
            shown = tomorrow
        }

        let started = Prayer.allCases.map { today.time(of: $0) }.filter { $0 <= date }
        let previous: Date
        if let latest = started.max() {
            previous = latest
        } else if let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: date),
                  let yesterday = service.prayerDay(for: place, on: yesterdayDate) {
            previous = yesterday.isha
        } else {
            previous = calendar.startOfDay(for: date)
        }

        return PrayerWidgetEntry(
            date: date,
            timeZone: place.timeZone,
            isFallback: place.isFallback,
            rows: Prayer.allCases.map { PrayerWidgetRow(prayer: $0, time: shown.time(of: $0)) },
            next: today.nextPrayer(after: date),
            previousStart: previous,
            phase: today.skyPhase(at: date),
            currentPeriodName: today.currentPeriodName(at: date)
        )
    }

    /// The entry that is showing at `date`: the last one that took effect at or before it.
    static func entry(in entries: [PrayerWidgetEntry], at date: Date) -> PrayerWidgetEntry? {
        entries.last { $0.date <= date }
    }
}
