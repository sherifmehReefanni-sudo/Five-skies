import XCTest
@testable import FiveSkies

/// Obligatory rakah counts on the day view (plan N4).
final class RakahCountTests: XCTestCase {
    func testObligatoryCounts() {
        XCTAssertEqual(RakahCount.obligatory(for: .fajr), 2)
        XCTAssertEqual(RakahCount.obligatory(for: .dhuhr), 4)
        XCTAssertEqual(RakahCount.obligatory(for: .asr), 4)
        XCTAssertEqual(RakahCount.obligatory(for: .maghrib), 3)
        XCTAssertEqual(RakahCount.obligatory(for: .isha), 4)
        XCTAssertEqual(Prayer.allCases.compactMap { RakahCount.obligatory(for: $0) }.reduce(0, +), 17)
    }

    func testCaption() {
        XCTAssertEqual(RakahCount.caption(for: 2), "2 rakahs")
        XCTAssertEqual(RakahCount.caption(for: 3), "3 rakahs")
        XCTAssertNil(RakahCount.caption(for: nil))
        XCTAssertNil(RakahCount.caption(for: 0))
    }

    func testPrayerRowsCarryCountsAndSunriseHasNone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        // 2026-11-27 is a Friday: Dhuhr still shows 4, nothing different.
        func at(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
        }
        let day = PrayerDay(
            fajr: try at(27, 5, 30),
            sunrise: try at(27, 6, 50),
            dhuhr: try at(27, 12, 0),
            asr: try at(27, 14, 40),
            maghrib: try at(27, 16, 35),
            isha: try at(27, 18, 0),
            tomorrowFajr: try at(28, 5, 31)
        )
        let schedule = DaySchedule.make(day: day, middleOfNight: try at(27, 23, 15), lastThirdOfNight: try at(28, 2, 0))
        let rows = DayViewContent.prayerRows(for: schedule, ishaEnd: .middleOfNight)
        XCTAssertEqual(rows.map(\.id), ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])
        XCTAssertEqual(rows.map(\.rakahs), [2, nil, 4, 4, 3, 4])
        XCTAssertEqual(rows.map(\.rakahCaption), ["2 rakahs", nil, "4 rakahs", "4 rakahs", "3 rakahs", "4 rakahs"])

        let others = [DayViewContent.duhaRow(for: schedule)]
            + DayViewContent.discouragedRows(for: schedule)
            + DayViewContent.nightRows(for: schedule)
            + DayViewContent.fastingRows(for: schedule)
        XCTAssertTrue(others.allSatisfy { $0.rakahs == nil && $0.rakahCaption == nil })
    }
}
