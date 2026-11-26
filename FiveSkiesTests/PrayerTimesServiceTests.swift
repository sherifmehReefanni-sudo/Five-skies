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
}
