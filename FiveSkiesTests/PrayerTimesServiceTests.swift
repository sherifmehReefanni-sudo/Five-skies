import XCTest
@testable import FiveSkies

final class PrayerTimesServiceTests: XCTestCase {
    func testMakkahTimesAreOrderedAndOnTheLocalDay() throws {
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = riyadh
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))

        let service = PrayerTimesService(timeZone: riyadh)
        let day = try XCTUnwrap(service.prayerDay(at: .makkah, on: date))

        let ordered = [day.fajr, day.sunrise, day.dhuhr, day.asr, day.maghrib, day.isha]
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(earlier, later)
        }
        for time in ordered {
            XCTAssertTrue(calendar.isDate(time, inSameDayAs: date), "\(time) is not on the expected day in Riyadh")
        }

        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: date))
        XCTAssertGreaterThan(day.tomorrowFajr, day.isha)
        XCTAssertTrue(calendar.isDate(day.tomorrowFajr, inSameDayAs: nextDay))
    }

    func testMakkahFallbackTimesAreInMakkahsZoneWhateverTheDeviceZone() throws {
        let place = Place.makkahFallback
        XCTAssertEqual(place.timeZone.identifier, "Asia/Riyadh")
        let calendar = place.calendar
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))

        let deviceZones = ["America/Los_Angeles", "America/New_York", "UTC", "Asia/Tokyo", "Pacific/Kiritimati"]
        for identifier in deviceZones {
            let deviceZone = try XCTUnwrap(TimeZone(identifier: identifier))
            let service = PrayerTimesService(timeZone: deviceZone)
            let day = try XCTUnwrap(service.prayerDay(for: place, on: date))

            let fajrHour = calendar.component(.hour, from: day.fajr)
            let maghribHour = calendar.component(.hour, from: day.maghrib)
            XCTAssertTrue((3...6).contains(fajrHour), "Fajr hour \(fajrHour) with device zone \(identifier)")
            XCTAssertTrue((17...19).contains(maghribHour), "Maghrib hour \(maghribHour) with device zone \(identifier)")
            XCTAssertTrue(calendar.isDate(day.fajr, inSameDayAs: date), "Fajr is not on the Makkah day for \(identifier)")
        }
    }

    func testTileTimesSplitThePeriodOnlyInTwelveHourLocales() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 17, minute: 34)))

        let twelveHour = TileTimeFormat(timeZone: utc, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(twelveHour.usesTwelveHourClock)
        XCTAssertEqual(twelveHour.time(date), "5:34")
        XCTAssertEqual(twelveHour.period(date), "PM")

        let twentyFourHour = TileTimeFormat(timeZone: utc, locale: Locale(identifier: "en_GB"))
        XCTAssertFalse(twentyFourHour.usesTwelveHourClock)
        XCTAssertEqual(twentyFourHour.time(date), "17:34")
        XCTAssertNil(twentyFourHour.period(date))
    }
}
