import XCTest
@testable import FiveSkies

final class SettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "SettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.calculationMethod, .northAmerica)
        XCTAssertEqual(settings.asrRule, .standard)
        XCTAssertEqual(settings.reminderMinutesBefore, 0)
        for prayer in Prayer.allCases {
            XCTAssertEqual(settings.alertMode(for: prayer), .sound, "\(prayer) should default to sound")
        }
        XCTAssertTrue(settings.alertPreferences.wantsAnyAlert)
    }

    func testRoundTripsAcrossInstances() {
        let writer = AppSettings(defaults: defaults)
        writer.calculationMethod = .ummAlQura
        writer.asrRule = .hanafi
        writer.reminderMinutesBefore = 15
        writer.setAlertMode(.off, for: .maghrib)
        writer.setAlertMode(.silent, for: .isha)

        let reader = AppSettings(defaults: defaults)
        XCTAssertEqual(reader.calculationMethod, .ummAlQura)
        XCTAssertEqual(reader.asrRule, .hanafi)
        XCTAssertEqual(reader.reminderMinutesBefore, 15)
        XCTAssertEqual(reader.alertMode(for: .maghrib), .off)
        XCTAssertEqual(reader.alertMode(for: .isha), .silent)
        XCTAssertEqual(reader.alertMode(for: .fajr), .sound)
        XCTAssertEqual(reader.snapshot, writer.snapshot)
    }

    func testUnknownStoredValuesFallBackToDefaults() {
        defaults.set("notAMethod", forKey: AppSettings.Keys.calculationMethod)
        defaults.set(7, forKey: AppSettings.Keys.reminderMinutesBefore)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.calculationMethod, .northAmerica)
        XCTAssertEqual(settings.reminderMinutesBefore, 0)
    }

    func testEveryCalculationMethodMapsToAdhan() throws {
        let newYork = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for method in PrayerCalculationMethod.allCases {
            XCTAssertEqual(method.adhanMethodName, method.rawValue)
            XCTAssertFalse(method.displayName.isEmpty)
            let service = PrayerTimesService(timeZone: utc).applying(method: method, asrRule: .standard)
            XCTAssertNotNil(service.prayerDay(at: .makkah, on: date), "\(method) gave no times for Makkah")
            XCTAssertNotNil(service.prayerDay(at: newYork, on: date), "\(method) gave no times for New York")
        }
    }

    func testAsrRuleMapping() throws {
        XCTAssertEqual(AsrRule.standard.shadowFactor, 1)
        XCTAssertEqual(AsrRule.hanafi.shadowFactor, 2)
        XCTAssertEqual(AsrRule.standard.displayName, "Standard (Shafi'i, Maliki, Hanbali)")
        XCTAssertEqual(AsrRule.hanafi.displayName, "Hanafi")

        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let base = PrayerTimesService(timeZone: riyadh)
        let standard = try XCTUnwrap(base.applying(method: .ummAlQura, asrRule: .standard).prayerDay(at: .makkah, on: date))
        let hanafi = try XCTUnwrap(base.applying(method: .ummAlQura, asrRule: .hanafi).prayerDay(at: .makkah, on: date))
        XCTAssertGreaterThan(hanafi.asr, standard.asr)
        XCTAssertEqual(hanafi.dhuhr, standard.dhuhr)
    }

    func testAlertAdditionsDefaults() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.endReminderMinutes, 0)
        XCTAssertFalse(settings.nightAlarmEnabled)
        XCTAssertEqual(settings.nightAlarmAnchor, .lastThirdOfNight)
        XCTAssertEqual(settings.nightAlarmOffsetMinutes, 0)
        XCTAssertEqual(settings.nightAlarmWeekdays, Set(1...7))

        let prefs = settings.alertPreferences
        XCTAssertEqual(prefs.endReminderMinutes, 0)
        XCTAssertEqual(prefs.ishaEnd, settings.ishaEnd)
        XCTAssertFalse(prefs.nightAlarm.isEnabled)
        XCTAssertEqual(prefs.nightAlarm, NightAlarmSettings())
    }

    func testAlertAdditionsRoundTrip() {
        let writer = AppSettings(defaults: defaults)
        writer.endReminderMinutes = 20
        writer.ishaEnd = .fajr
        writer.nightAlarmEnabled = true
        writer.nightAlarmAnchor = .fajr
        writer.nightAlarmOffsetMinutes = -45
        writer.nightAlarmWeekdays = [2, 6]

        let reader = AppSettings(defaults: defaults)
        XCTAssertEqual(reader.endReminderMinutes, 20)
        XCTAssertTrue(reader.nightAlarmEnabled)
        XCTAssertEqual(reader.nightAlarmAnchor, .fajr)
        XCTAssertEqual(reader.nightAlarmOffsetMinutes, -45)
        XCTAssertEqual(reader.nightAlarmWeekdays, [2, 6])
        XCTAssertEqual(reader.alertPreferences, writer.alertPreferences)
        XCTAssertEqual(reader.alertPreferences.ishaEnd, .fajr)
        XCTAssertEqual(
            reader.alertPreferences.nightAlarm,
            NightAlarmSettings(isEnabled: true, anchor: .fajr, offsetMinutes: -45, weekdays: [2, 6])
        )
        XCTAssertEqual(reader.snapshot, writer.snapshot)
    }

    func testAlertAdditionsInvalidStoredValuesFallBack() {
        defaults.set(7, forKey: AppSettings.Keys.endReminderMinutes)
        defaults.set("noon", forKey: AppSettings.Keys.nightAlarmAnchor)
        defaults.set(13, forKey: AppSettings.Keys.nightAlarmOffset)
        defaults.set([0, 9], forKey: AppSettings.Keys.nightAlarmWeekdays)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.endReminderMinutes, 0)
        XCTAssertEqual(settings.nightAlarmAnchor, .lastThirdOfNight)
        XCTAssertEqual(settings.nightAlarmOffsetMinutes, 0)
        XCTAssertEqual(settings.nightAlarmWeekdays, Set(1...7))
    }

    func testNightAlarmAloneNeedsNotificationPermission() {
        var off: [Prayer: AlertMode] = [:]
        for prayer in Prayer.allCases { off[prayer] = .off }
        var prefs = AlertPreferences(modes: off, reminderMinutesBefore: 0)
        XCTAssertFalse(prefs.wantsAnyAlert)
        XCTAssertFalse(prefs.needsNotificationPermission)
        prefs.nightAlarm.isEnabled = true
        XCTAssertFalse(prefs.wantsAnyAlert)
        XCTAssertTrue(prefs.needsNotificationPermission)
    }

    func testChangingAlertAdditionsChangesTheSnapshot() {
        let settings = AppSettings(defaults: defaults)
        let before = settings.snapshot
        settings.nightAlarmOffsetMinutes = 15
        XCTAssertNotEqual(settings.snapshot, before)
        let middle = settings.snapshot
        settings.endReminderMinutes = 10
        XCTAssertNotEqual(settings.snapshot, middle)
    }
}
