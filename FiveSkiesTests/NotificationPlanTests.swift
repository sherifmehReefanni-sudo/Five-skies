import XCTest
@testable import FiveSkies

final class NotificationPlanTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    private func prayerDay(_ day: Int) throws -> PrayerDay {
        PrayerDay(
            fajr: try date(day, 5, 30),
            sunrise: try date(day, 6, 50),
            dhuhr: try date(day, 12, 0),
            asr: try date(day, 14, 40),
            maghrib: try date(day, 16, 35),
            isha: try date(day, 18, 0),
            tomorrowFajr: try date(day + 1, 5, 31)
        )
    }

    private func preferences(
        _ overrides: [Prayer: AlertMode] = [:],
        reminder: Int = 0
    ) -> AlertPreferences {
        var modes: [Prayer: AlertMode] = [:]
        for prayer in Prayer.allCases {
            modes[prayer] = overrides[prayer] ?? .sound
        }
        return AlertPreferences(modes: modes, reminderMinutesBefore: reminder)
    }

    func testSkipsPastPrayersAndIncludesTomorrow() throws {
        let now = try date(26, 13, 0)
        let plan = NotificationPlan.make(
            days: [try prayerDay(26), try prayerDay(27)],
            preferences: preferences(),
            now: now,
            calendar: calendar
        )
        let ids = plan.map { $0.id }
        XCTAssertEqual(ids, [
            "prayer-2026-11-26-asr",
            "prayer-2026-11-26-maghrib",
            "prayer-2026-11-26-isha",
            "prayer-2026-11-27-fajr",
            "prayer-2026-11-27-dhuhr",
            "prayer-2026-11-27-asr",
            "prayer-2026-11-27-maghrib",
            "prayer-2026-11-27-isha"
        ])
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now })

        let asr = try XCTUnwrap(plan.first { $0.id == "prayer-2026-11-26-asr" })
        XCTAssertEqual(asr.title, "Asr")
        XCTAssertEqual(asr.body, "It is time for Asr.")
        XCTAssertEqual(asr.fireDate, try date(26, 14, 40))
        XCTAssertTrue(asr.hasSound)
    }

    func testOffPrayersAreSkippedAndSilentHasNoSound() throws {
        let plan = NotificationPlan.make(
            days: [try prayerDay(26)],
            preferences: preferences([.maghrib: .off, .isha: .silent]),
            now: try date(26, 0, 0),
            calendar: calendar
        )
        XCTAssertFalse(plan.contains { $0.id.hasSuffix("-maghrib") })
        XCTAssertEqual(plan.count, 4)
        let isha = try XCTUnwrap(plan.first { $0.id == "prayer-2026-11-26-isha" })
        XCTAssertFalse(isha.hasSound)
    }

    func testRemindersFireTheChosenMinutesBefore() throws {
        let now = try date(26, 14, 30)
        let plan = NotificationPlan.make(
            days: [try prayerDay(26)],
            preferences: preferences(reminder: 15),
            now: now,
            calendar: calendar
        )
        // Asr is at 14:40, so its reminder at 14:25 is already past and only the prayer entry stays.
        XCTAssertNil(plan.first { $0.id == "reminder-2026-11-26-asr" })
        XCTAssertNotNil(plan.first { $0.id == "prayer-2026-11-26-asr" })

        let maghrib = try XCTUnwrap(plan.first { $0.id == "reminder-2026-11-26-maghrib" })
        XCTAssertEqual(maghrib.fireDate, try date(26, 16, 20))
        XCTAssertEqual(maghrib.title, "Maghrib in 15 minutes")
        XCTAssertEqual(maghrib.body, "Prepare for prayer.")
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("reminder-") }.count, 2)
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("prayer-") }.count, 3)
    }

    func testIdsAreStableAcrossRuns() throws {
        let days = [try prayerDay(26), try prayerDay(27)]
        let first = NotificationPlan.make(days: days, preferences: preferences(reminder: 10), now: try date(26, 3, 0), calendar: calendar)
        let second = NotificationPlan.make(days: days, preferences: preferences(reminder: 10), now: try date(26, 4, 0), calendar: calendar)
        XCTAssertEqual(first.map { $0.id }, second.map { $0.id })
        XCTAssertEqual(Set(first.map { $0.id }).count, first.count)
        XCTAssertEqual(first.count, 20)
        XCTAssertTrue(first.allSatisfy { NotificationPlan.isOwned($0.id) })
    }

    func testNothingWhenAllOff() throws {
        var off: [Prayer: AlertMode] = [:]
        for prayer in Prayer.allCases { off[prayer] = .off }
        let prefs = preferences(off, reminder: 30)
        XCTAssertFalse(prefs.wantsAnyAlert)
        let plan = NotificationPlan.make(days: [try prayerDay(26)], preferences: prefs, now: try date(26, 0, 0), calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: Reminder before a prayer's time ends

    private func schedule(_ day: Int) throws -> DaySchedule {
        DaySchedule.make(
            day: try prayerDay(day),
            middleOfNight: try date(day, 23, 15),
            lastThirdOfNight: try date(day + 1, 2, 0)
        )
    }

    private func endPreferences(
        _ overrides: [Prayer: AlertMode] = [:],
        minutes: Int,
        ishaEnd: IshaEndRule = .middleOfNight
    ) -> AlertPreferences {
        var prefs = preferences(overrides)
        prefs.endReminderMinutes = minutes
        prefs.ishaEnd = ishaEnd
        return prefs
    }

    func testEndRemindersFireBeforeEachWindowEnds() throws {
        let plan = NotificationPlan.endReminders(
            schedules: [try schedule(26)],
            preferences: endPreferences(minutes: 15),
            now: try date(26, 0, 0),
            calendar: calendar
        )
        XCTAssertEqual(plan.map { $0.id }, [
            "end-2026-11-26-fajr",
            "end-2026-11-26-dhuhr",
            "end-2026-11-26-asr",
            "end-2026-11-26-maghrib",
            "end-2026-11-26-isha"
        ])
        let asr = try XCTUnwrap(plan.first { $0.id == "end-2026-11-26-asr" })
        XCTAssertEqual(asr.title, "Asr ends in 15 minutes")
        XCTAssertEqual(asr.body, "There is still time to pray.")
        XCTAssertEqual(asr.fireDate, try date(26, 16, 20))
        XCTAssertTrue(asr.hasSound)
        XCTAssertFalse(asr.isTimeSensitive)
        XCTAssertEqual(plan.first { $0.id.hasSuffix("fajr") }?.fireDate, try date(26, 6, 35))
        XCTAssertEqual(plan.first { $0.id.hasSuffix("dhuhr") }?.fireDate, try date(26, 14, 25))
        XCTAssertEqual(plan.first { $0.id.hasSuffix("maghrib") }?.fireDate, try date(26, 17, 45))
        XCTAssertEqual(plan.first { $0.id.hasSuffix("isha") }?.fireDate, try date(26, 23, 0))
        XCTAssertTrue(plan.allSatisfy { NotificationPlan.isOwned($0.id) })
    }

    func testEndReminderForIshaFollowsTheIshaEndSetting() throws {
        let plan = NotificationPlan.endReminders(
            schedules: [try schedule(26)],
            preferences: endPreferences(minutes: 30, ishaEnd: .fajr),
            now: try date(26, 0, 0),
            calendar: calendar
        )
        let isha = try XCTUnwrap(plan.first { $0.id == "end-2026-11-26-isha" })
        XCTAssertEqual(isha.fireDate, try date(27, 5, 1))
        XCTAssertEqual(isha.title, "Isha ends in 30 minutes")
    }

    func testEndRemindersSkipOffPastAndShortWindows() throws {
        let short = PrayerDay(
            fajr: try date(26, 5, 30),
            sunrise: try date(26, 5, 40),
            dhuhr: try date(26, 12, 0),
            asr: try date(26, 14, 40),
            maghrib: try date(26, 16, 35),
            isha: try date(26, 18, 0),
            tomorrowFajr: try date(27, 5, 31)
        )
        let day = DaySchedule.make(day: short, middleOfNight: try date(26, 23, 15), lastThirdOfNight: try date(27, 2, 0))
        let plan = NotificationPlan.endReminders(
            schedules: [day],
            preferences: endPreferences([.asr: .off, .isha: .silent], minutes: 15),
            now: try date(26, 14, 30),
            calendar: calendar
        )
        // Fajr's window is 10 minutes (shorter than 15), Dhuhr's reminder at 14:25 has passed, Asr is off.
        XCTAssertEqual(plan.map { $0.id }, ["end-2026-11-26-maghrib", "end-2026-11-26-isha"])
        XCTAssertFalse(try XCTUnwrap(plan.last).hasSound)
    }

    func testNoEndRemindersWhenOff() throws {
        let plan = NotificationPlan.endReminders(
            schedules: [try schedule(26)],
            preferences: endPreferences(minutes: 0),
            now: try date(26, 0, 0),
            calendar: calendar
        )
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: Night alarm fallback and the pending limit

    func testNightAlarmNotificationIsTimeSensitiveWithSound() throws {
        let alarm = PlannedNightAlarm(id: "night-2026-11-27", fireDate: try date(27, 2, 0))
        let plan = NotificationPlan.full(
            days: [],
            schedules: [],
            preferences: preferences(),
            nightAlarms: [alarm, PlannedNightAlarm(id: "night-2026-11-25", fireDate: try date(25, 2, 0))],
            now: try date(26, 12, 0),
            calendar: calendar
        )
        XCTAssertEqual(plan.map { $0.id }, ["night-2026-11-27"])
        let item = try XCTUnwrap(plan.first)
        XCTAssertTrue(item.isTimeSensitive)
        XCTAssertTrue(item.hasSound)
        XCTAssertEqual(item.title, "Night alarm")
        XCTAssertEqual(item.fireDate, try date(27, 2, 0))
        XCTAssertTrue(NotificationPlan.isOwned(item.id))
    }

    func testFullPlanForTodayAndTomorrowStaysUnderTheLimit() throws {
        var prefs = endPreferences(minutes: 10)
        prefs.reminderMinutesBefore = 15
        let plan = NotificationPlan.full(
            days: [try prayerDay(26), try prayerDay(27)],
            schedules: [try schedule(26), try schedule(27)],
            preferences: prefs,
            nightAlarms: [
                PlannedNightAlarm(id: "night-2026-11-27", fireDate: try date(27, 2, 0)),
                PlannedNightAlarm(id: "night-2026-11-28", fireDate: try date(28, 2, 0))
            ],
            now: try date(26, 0, 0),
            calendar: calendar
        )
        // 2 days x 5 prayers x (start, reminder, end) + 2 night alarms.
        XCTAssertEqual(plan.count, 32)
        XCTAssertLessThanOrEqual(plan.count, NotificationPlan.pendingLimit)
        XCTAssertEqual(Set(plan.map { $0.id }).count, plan.count)
        XCTAssertEqual(plan.map { $0.fireDate }, plan.map { $0.fireDate }.sorted())
    }

    func testCapDropsTheFurthestFirst() throws {
        var prefs = endPreferences(minutes: 10)
        prefs.reminderMinutesBefore = 15
        let days = try (1...7).map { try self.prayerDay($0) }
        let schedules = try (1...7).map { try self.schedule($0) }
        let uncapped = NotificationPlan.full(
            days: days,
            schedules: schedules,
            preferences: prefs,
            nightAlarms: [],
            now: try date(1, 0, 0),
            calendar: calendar,
            limit: Int.max
        )
        XCTAssertEqual(uncapped.count, 105)

        let capped = NotificationPlan.full(
            days: days,
            schedules: schedules,
            preferences: prefs,
            nightAlarms: [],
            now: try date(1, 0, 0),
            calendar: calendar
        )
        XCTAssertEqual(capped.count, NotificationPlan.pendingLimit)
        XCTAssertEqual(capped.map { $0.id }, Array(uncapped.prefix(NotificationPlan.pendingLimit)).map { $0.id })
        let lastKept = try XCTUnwrap(capped.last).fireDate
        let firstDropped = uncapped[NotificationPlan.pendingLimit].fireDate
        XCTAssertLessThanOrEqual(lastKept, firstDropped)

        let small = NotificationPlan.capped(uncapped.reversed(), limit: 3)
        XCTAssertEqual(small.map { $0.id }, uncapped.prefix(3).map { $0.id })
        XCTAssertTrue(NotificationPlan.capped(uncapped, limit: 0).isEmpty)
    }
}
