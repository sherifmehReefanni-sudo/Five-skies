import XCTest
@testable import FiveSkies

/// Private mode (plan N6): same alerts, same times, ids and sounds, no prayer name, no religious words.
final class PrivateRemindersTests: XCTestCase {
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

    private func schedule(_ day: Int) throws -> DaySchedule {
        DaySchedule.make(
            day: try prayerDay(day),
            middleOfNight: try date(day, 23, 15),
            lastThirdOfNight: try date(day + 1, 2, 0)
        )
    }

    /// Every kind of alert on: start, reminder, end of time, with one prayer silent.
    private func preferences() -> AlertPreferences {
        var modes: [Prayer: AlertMode] = [:]
        for prayer in Prayer.allCases {
            modes[prayer] = .sound
        }
        modes[.isha] = .silent
        var prefs = AlertPreferences(modes: modes, reminderMinutesBefore: 15)
        prefs.endReminderMinutes = 10
        return prefs
    }

    private func fullPlan(isPrivate: Bool?) throws -> [PlannedNotification] {
        let days = [try prayerDay(26), try prayerDay(27)]
        let schedules = [try schedule(26), try schedule(27)]
        let nights = [PlannedNightAlarm(id: "night-2026-11-27", fireDate: try date(27, 2, 0))]
        let now = try date(26, 0, 0)
        guard let isPrivate = isPrivate else {
            return NotificationPlan.full(
                days: days, schedules: schedules, preferences: preferences(),
                nightAlarms: nights, now: now, calendar: calendar
            )
        }
        return NotificationPlan.full(
            days: days, schedules: schedules, preferences: preferences(),
            nightAlarms: nights, now: now, calendar: calendar, isPrivate: isPrivate
        )
    }

    private let bannedWords = ["pray", "salah", "salat", "allah", "mosque", "adhan", "azan", "islam", "muslim", "quran", "night alarm"]

    func testPrivateTextHasNoPrayerNameAndNoReligiousWords() throws {
        let plan = try fullPlan(isPrivate: true)
        XCTAssertEqual(plan.count, 31, "2 days x 5 prayers x 3 alerts + 1 night alarm")
        for item in plan {
            let text = (item.title + " " + item.body).lowercased()
            for prayer in Prayer.allCases {
                XCTAssertFalse(text.contains(prayer.displayName.lowercased()), "\(item.id): \(text)")
                XCTAssertFalse(text.contains(prayer.plainLabel.lowercased()), "\(item.id): \(text)")
            }
            for word in bannedWords {
                XCTAssertFalse(text.contains(word), "\(item.id): \(text)")
            }
        }
    }

    func testPrivateTitlesAndBodies() throws {
        let plan = try fullPlan(isPrivate: true)
        for item in plan where item.id.hasPrefix(NotificationPlan.nightPrefix) {
            XCTAssertEqual(item.title, "Alarm")
            XCTAssertEqual(item.body, "This is the wake time you set.")
        }
        let prayerAlerts = plan.filter { !$0.id.hasPrefix(NotificationPlan.nightPrefix) }
        XCTAssertEqual(prayerAlerts.count, 30)
        for item in prayerAlerts {
            XCTAssertEqual(item.title, "Reminder", item.id)
            XCTAssertEqual(item.body, "You set this reminder.", item.id)
        }
        XCTAssertEqual(NotificationPlan.nightAlarmNotifications(
            [PlannedNightAlarm(id: "night-2026-11-27", fireDate: try date(27, 2, 0))],
            isPrivate: true
        ).first?.title, "Alarm")
    }

    func testPrivateKeepsTimesIdsAndSounds() throws {
        let normal = try fullPlan(isPrivate: false)
        let hidden = try fullPlan(isPrivate: true)
        XCTAssertEqual(normal.map(\.id), hidden.map(\.id))
        XCTAssertEqual(normal.map(\.fireDate), hidden.map(\.fireDate))
        XCTAssertEqual(normal.map(\.hasSound), hidden.map(\.hasSound))
        XCTAssertEqual(normal.map(\.isTimeSensitive), hidden.map(\.isTimeSensitive))
        XCTAssertTrue(hidden.contains { !$0.hasSound }, "Silent Isha stays silent")
    }

    func testDefaultIsNotPrivateAndWordingIsUnchanged() throws {
        let byDefault = try fullPlan(isPrivate: nil)
        XCTAssertEqual(byDefault, try fullPlan(isPrivate: false))

        let asr = try XCTUnwrap(byDefault.first { $0.id == "prayer-2026-11-26-asr" })
        XCTAssertEqual(asr.title, "Asr")
        XCTAssertEqual(asr.body, "It is time for Asr.")
        let reminder = try XCTUnwrap(byDefault.first { $0.id == "reminder-2026-11-26-maghrib" })
        XCTAssertEqual(reminder.title, "Maghrib in 15 minutes")
        XCTAssertEqual(reminder.body, "Prepare for prayer.")
        let end = try XCTUnwrap(byDefault.first { $0.id == "end-2026-11-26-dhuhr" })
        XCTAssertEqual(end.title, "Dhuhr ends in 10 minutes")
        XCTAssertEqual(end.body, "There is still time to pray.")
        let night = try XCTUnwrap(byDefault.first { $0.id == "night-2026-11-27" })
        XCTAssertEqual(night.title, "Night alarm")
        XCTAssertEqual(night.body, "This is the wake time you set.")
    }

    func testMakeAndEndRemindersTakeThePrivateFlag() throws {
        let make = NotificationPlan.make(
            days: [try prayerDay(26)], preferences: preferences(),
            now: try date(26, 0, 0), calendar: calendar, isPrivate: true
        )
        XCTAssertEqual(make.count, 10)
        XCTAssertTrue(make.allSatisfy { $0.title == "Reminder" && $0.body == "You set this reminder." })

        let ends = NotificationPlan.endReminders(
            schedules: [try schedule(26)], preferences: preferences(),
            now: try date(26, 0, 0), calendar: calendar, isPrivate: true
        )
        XCTAssertEqual(ends.count, 5)
        XCTAssertTrue(ends.allSatisfy { $0.title == "Reminder" && $0.body == "You set this reminder." })
    }
}
