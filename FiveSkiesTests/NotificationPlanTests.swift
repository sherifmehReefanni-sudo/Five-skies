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
}
