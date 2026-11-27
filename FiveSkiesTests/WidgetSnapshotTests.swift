import XCTest
@testable import FiveSkies

final class WidgetSnapshotTests: XCTestCase {
    private let config = SharedPrayerConfig.fallback

    private func startOfTestDay() throws -> Date {
        let calendar = config.place.calendar
        return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15)))
    }

    private func testDay() throws -> PrayerDay {
        let service = PrayerTimesService().applying(method: config.calculationMethod, asrRule: config.asrRule)
        return try XCTUnwrap(service.prayerDay(for: config.place, on: startOfTestDay()))
    }

    func testEntryDatesAreStrictlyIncreasing() throws {
        let now = try startOfTestDay()
        for step in [nil, PrayerWidgetTimeline.progressStep] {
            let dates = PrayerWidgetTimeline.entries(config: config, now: now, progressStep: step).map(\.date)
            XCTAssertGreaterThan(dates.count, 1)
            XCTAssertEqual(dates.first, now)
            for (earlier, later) in zip(dates, dates.dropFirst()) {
                XCTAssertLessThan(earlier, later)
            }
        }
    }

    func testEntriesCoverEveryPrayerBoundaryOfTodayAndTheNextMidnight() throws {
        let now = try startOfTestDay()
        let day = try testDay()
        let dates = PrayerWidgetTimeline.entries(config: config, now: now).map(\.date)
        for prayer in Prayer.allCases {
            XCTAssertTrue(dates.contains(day.time(of: prayer)), "No entry at \(prayer.displayName)")
        }
        XCTAssertTrue(dates.contains(day.sunrise), "No entry at sunrise")
        let calendar = config.place.calendar
        let midnight = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        XCTAssertTrue(dates.contains(midnight), "No entry at the next midnight")
    }

    func testEntriesStartingMidDayStillCoverTheRemainingBoundaries() throws {
        let day = try testDay()
        let now = day.dhuhr.addingTimeInterval(60)
        let dates = PrayerWidgetTimeline.entries(config: config, now: now).map(\.date)
        XCTAssertEqual(dates.first, now)
        for prayer in [Prayer.asr, .maghrib, .isha] {
            XCTAssertTrue(dates.contains(day.time(of: prayer)), "No entry at \(prayer.displayName)")
        }
        XCTAssertTrue(dates.contains(day.tomorrowFajr), "No entry at tomorrow's Fajr")
    }

    func testEntryInEffectReportsTheRightNextPrayerAndPhase() throws {
        let now = try startOfTestDay()
        let day = try testDay()
        let entries = PrayerWidgetTimeline.entries(config: config, now: now)

        let cases: [(Date, Prayer, Date, Prayer)] = [
            (day.fajr.addingTimeInterval(-600), .fajr, day.fajr, .isha),
            (day.fajr.addingTimeInterval(600), .dhuhr, day.dhuhr, .fajr),
            (day.sunrise.addingTimeInterval(600), .dhuhr, day.dhuhr, .dhuhr),
            (day.asr.addingTimeInterval(600), .maghrib, day.maghrib, .asr),
            (day.maghrib.addingTimeInterval(600), .isha, day.isha, .maghrib),
            (day.isha.addingTimeInterval(3600), .fajr, day.tomorrowFajr, .isha)
        ]
        for (moment, nextPrayer, nextTime, phase) in cases {
            let entry = try XCTUnwrap(PrayerWidgetTimeline.entry(in: entries, at: moment))
            XCTAssertEqual(entry.next.prayer, nextPrayer, "Next prayer at \(moment)")
            XCTAssertEqual(entry.next.time, nextTime, "Next prayer time at \(moment)")
            XCTAssertEqual(entry.phase, phase, "Phase at \(moment)")
            XCTAssertEqual(entry.rows.map(\.prayer), Prayer.allCases)
            XCTAssertEqual(entry.timeZone.identifier, "Asia/Riyadh")
        }
    }

    func testProgressRunsFromThePreviousPrayerToTheNext() throws {
        let day = try testDay()
        let halfway = day.asr.addingTimeInterval(day.maghrib.timeIntervalSince(day.asr) / 2)
        let entry = try XCTUnwrap(PrayerWidgetTimeline.entry(at: halfway, config: config))
        XCTAssertEqual(entry.previousStart, day.asr)
        XCTAssertEqual(entry.progress, 0.5, accuracy: 0.001)

        let atStart = try XCTUnwrap(PrayerWidgetTimeline.entry(at: day.asr, config: config))
        XCTAssertEqual(atStart.next.prayer, .maghrib)
        XCTAssertEqual(atStart.progress, 0, accuracy: 0.001)
    }

    func testAfterIshaTheRowsShowTheNextDay() throws {
        let day = try testDay()
        let entry = try XCTUnwrap(PrayerWidgetTimeline.entry(at: day.isha.addingTimeInterval(60), config: config))
        XCTAssertEqual(entry.rows.first?.time, day.tomorrowFajr)
    }

    func testWidgetTextUsesThePlaceTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
        let format = TileTimeFormat(timeZone: utc)
        let expected = format.period(date).map { "\(format.time(date)) \($0)" } ?? format.time(date)
        XCTAssertEqual(PrayerWidgetText.time(date, timeZone: utc), expected)
        XCTAssertEqual(PrayerWidgetText.countdown(from: date, to: date.addingTimeInterval(72 * 60)), "in 1h 12m")
        XCTAssertEqual(PrayerWidgetText.countdown(from: date, to: date.addingTimeInterval(30)), "in 1m")
    }

    func testSharedConfigRoundTrips() throws {
        let suiteName = "WidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedPrayerConfigStore(defaults: defaults)
        XCTAssertNil(store.load())

        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let place = Place(coordinate: Coordinate(latitude: 40.29, longitude: -74.05), timeZone: zone, isFallback: false)
        let config = SharedPrayerConfig(place: place, calculationMethod: .egyptian, asrRule: .hanafi)

        XCTAssertTrue(store.save(config))
        XCTAssertFalse(store.save(config), "Saving the same value again should report no change")
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.place, place)
    }

    func testSharedConfigFallsBackSafely() throws {
        let missing = SharedPrayerConfigStore(defaults: nil)
        XCTAssertNil(missing.load())
        XCTAssertEqual(missing.loadOrFallback(), .fallback)
        XCTAssertFalse(missing.save(.fallback))
        XCTAssertEqual(missing.loadOrFallback().place, Place.makkahFallback)

        let suiteName = "WidgetSnapshotTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: SharedPrayerConfigStore.storageKey)
        XCTAssertEqual(SharedPrayerConfigStore(defaults: defaults).loadOrFallback(), .fallback)
    }
}
