import XCTest
@testable import FiveSkies

final class PrayerDayTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(hours: Double) -> Date {
        base.addingTimeInterval(hours * 3600)
    }

    private var day: PrayerDay {
        PrayerDay(
            fajr: at(hours: 5),
            sunrise: at(hours: 6.5),
            dhuhr: at(hours: 12),
            asr: at(hours: 15.5),
            maghrib: at(hours: 18),
            isha: at(hours: 19.5),
            tomorrowFajr: at(hours: 29)
        )
    }

    func testSkyPhaseAtTheMidpointOfEachWindow() {
        XCTAssertEqual(day.skyPhase(at: at(hours: 2)), .isha)
        XCTAssertEqual(day.skyPhase(at: at(hours: 5.75)), .fajr)
        XCTAssertEqual(day.skyPhase(at: at(hours: 11)), .dhuhr)
        XCTAssertEqual(day.skyPhase(at: at(hours: 16.375)), .asr)
        XCTAssertEqual(day.skyPhase(at: at(hours: 18.375)), .maghrib)
        XCTAssertEqual(day.skyPhase(at: at(hours: 24.25)), .isha)
    }

    func testCurrentPeriodNameIncludesMorningBetweenSunriseAndDhuhr() {
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 2)), "Isha")
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 5.5)), "Fajr")
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 9)), "Morning")
        XCTAssertNil(day.currentPrayer(at: at(hours: 9)))
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 13)), "Dhuhr")
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 17.5)), "Asr")
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 18.5)), "Maghrib")
        XCTAssertEqual(day.currentPeriodName(at: at(hours: 22)), "Isha")
    }

    func testMidpointHelperLandsInsideItsOwnPhase() {
        for phase in Prayer.allCases {
            XCTAssertEqual(day.skyPhase(at: day.midpoint(of: phase)), phase)
        }
    }

    func testSunsetSkyStartsFortyFiveMinutesBeforeMaghrib() {
        XCTAssertEqual(day.skyPhase(at: at(hours: 17.25).addingTimeInterval(-1)), .asr)
        XCTAssertEqual(day.skyPhase(at: at(hours: 17.25)), .maghrib)
    }

    func testNextPrayerWithinTheDay() {
        XCTAssertEqual(day.nextPrayer(after: at(hours: 11)), UpcomingPrayer(prayer: .dhuhr, time: at(hours: 12)))
        XCTAssertEqual(day.nextPrayer(after: at(hours: 1)), UpcomingPrayer(prayer: .fajr, time: at(hours: 5)))
    }

    func testNextPrayerRollsOverToTomorrowsFajrAfterIsha() {
        let expected = UpcomingPrayer(prayer: .fajr, time: at(hours: 29))
        XCTAssertEqual(day.nextPrayer(after: at(hours: 19.5)), expected)
        XCTAssertEqual(day.nextPrayer(after: at(hours: 23)), expected)
    }
}
