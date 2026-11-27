import XCTest
@testable import FiveSkies

final class NightAlarmPlanTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    /// A day in November 2026 (UTC) whose night has its last third at 02:40 the next morning
    /// and whose next Fajr is at 05:31.
    private func schedule(_ day: Int) throws -> DaySchedule {
        let prayerDay = PrayerDay(
            fajr: try date(day, 5, 30),
            sunrise: try date(day, 6, 50),
            dhuhr: try date(day, 12, 0),
            asr: try date(day, 14, 40),
            maghrib: try date(day, 16, 35),
            isha: try date(day, 18, 0),
            tomorrowFajr: try date(day + 1, 5, 31)
        )
        return DaySchedule.make(
            day: prayerDay,
            middleOfNight: try date(day, 23, 3),
            lastThirdOfNight: try date(day + 1, 2, 40)
        )
    }

    private func settings(
        anchor: NightAlarmAnchor = .lastThirdOfNight,
        offset: Int = 0,
        weekdays: Set<Int> = NightAlarmSettings.everyDay,
        enabled: Bool = true
    ) -> NightAlarmSettings {
        NightAlarmSettings(isEnabled: enabled, anchor: anchor, offsetMinutes: offset, weekdays: weekdays)
    }

    func testFireDateFollowsAnchorAndOffset() throws {
        let day = try schedule(26)
        XCTAssertEqual(
            NightAlarmPlan.fireDate(for: day, anchor: .lastThirdOfNight, offsetMinutes: 0),
            try date(27, 2, 40)
        )
        XCTAssertEqual(
            NightAlarmPlan.fireDate(for: day, anchor: .lastThirdOfNight, offsetMinutes: -15),
            try date(27, 2, 25)
        )
        XCTAssertEqual(
            NightAlarmPlan.fireDate(for: day, anchor: .fajr, offsetMinutes: -60),
            try date(27, 4, 31)
        )
        XCTAssertEqual(
            NightAlarmPlan.fireDate(for: day, anchor: .fajr, offsetMinutes: 10),
            try date(27, 5, 41)
        )
    }

    func testNextTwoNightsIncludingTheOneStillAheadAfterMidnight() throws {
        let schedules = [try schedule(25), try schedule(26), try schedule(27), try schedule(28)]
        // 01:00 on the 26th: the night after the 25th still has its alarm at 02:40 ahead.
        let alarms = NightAlarmPlan.upcoming(
            schedules: schedules,
            settings: settings(),
            now: try date(26, 1, 0),
            calendar: calendar
        )
        XCTAssertEqual(alarms.map { $0.id }, ["night-2026-11-26", "night-2026-11-27"])
        XCTAssertEqual(alarms.first?.fireDate, try date(26, 2, 40))
        XCTAssertEqual(alarms.count, NightAlarmPlan.maxScheduled)
    }

    func testPassedAlarmIsSkipped() throws {
        let schedules = [try schedule(25), try schedule(26), try schedule(27)]
        let now = try date(26, 3, 0)
        let alarms = NightAlarmPlan.upcoming(
            schedules: schedules,
            settings: settings(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(alarms.map { $0.id }, ["night-2026-11-27", "night-2026-11-28"])
        XCTAssertTrue(alarms.allSatisfy { $0.fireDate > now })
    }

    func testOnlyChosenRingDays() throws {
        let schedules = try (24...28).map { try self.schedule($0) }
        // Rings on Friday (6) only: the 27th, which is the night after Thursday the 26th.
        let alarms = NightAlarmPlan.upcoming(
            schedules: schedules,
            settings: settings(weekdays: [6]),
            now: try date(24, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(alarms.map { $0.id }, ["night-2026-11-27"])
    }

    func testOffAndZeroLimitGiveNothing() throws {
        let schedules = [try schedule(26), try schedule(27)]
        let now = try date(26, 12, 0)
        XCTAssertTrue(NightAlarmPlan.upcoming(schedules: schedules, settings: settings(enabled: false), now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(NightAlarmPlan.upcoming(schedules: schedules, settings: settings(), now: now, calendar: calendar, limit: 0).isEmpty)
    }

    func testDayKeyUsesTheGivenTimeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        // 02:40 UTC on the 27th is 21:40 on the 26th in New York (UTC-5 in November).
        let alarms = NightAlarmPlan.upcoming(
            schedules: [try schedule(26)],
            settings: settings(),
            now: try date(26, 12, 0),
            calendar: newYork
        )
        XCTAssertEqual(alarms.map { $0.id }, ["night-2026-11-26"])
    }

    func testRealTimesFallInsideTheNight() throws {
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let place = Place(coordinate: .makkah, timeZone: riyadh, isFallback: true)
        let service = PrayerTimesService(timeZone: riyadh).applying(method: .ummAlQura, asrRule: .standard)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = try XCTUnwrap(service.daySchedule(for: place, on: day))
        let lastThird = NightAlarmPlan.fireDate(for: schedule, anchor: .lastThirdOfNight, offsetMinutes: 0)
        XCTAssertGreaterThan(lastThird, schedule.day.isha)
        XCTAssertLessThan(lastThird, schedule.day.tomorrowFajr)
        XCTAssertGreaterThan(lastThird, schedule.middleOfNight)
    }

    func testOffsetLabels() {
        XCTAssertEqual(NightAlarmSettings.offsetLabel(-15), "15 minutes before")
        XCTAssertEqual(NightAlarmSettings.offsetLabel(0), "At the time")
        XCTAssertEqual(NightAlarmSettings.offsetLabel(10), "10 minutes after")
        XCTAssertEqual(NightAlarmSettings.offsetOptions.first, -60)
        XCTAssertEqual(NightAlarmSettings.offsetOptions.last, 60)
        XCTAssertEqual(NightAlarmSettings.offsetOptions.count, 25)
        XCTAssertTrue(NightAlarmSettings.offsetOptions.contains(0))
    }
}
