import XCTest
@testable import FiveSkies

final class NewToIslamSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NewToIslamSettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Settings

    func testBothSwitchesAreOffByDefault() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.newToIslam)
        XCTAssertFalse(settings.privateReminders)
        XCTAssertFalse(settings.alertPreferences.privateReminders)
    }

    func testKeysAreInTheBackedUpSettingsPrefix() {
        XCTAssertEqual(AppSettings.Keys.newToIslam, "settings.newToIslam")
        XCTAssertEqual(AppSettings.Keys.privateReminders, "settings.privateReminders")
    }

    func testSwitchesPersistAcrossInstances() {
        let writer = AppSettings(defaults: defaults)
        writer.newToIslam = true
        writer.privateReminders = true

        let reader = AppSettings(defaults: defaults)
        XCTAssertTrue(reader.newToIslam)
        XCTAssertTrue(reader.privateReminders)
        XCTAssertTrue(reader.alertPreferences.privateReminders)
        XCTAssertEqual(reader.snapshot, writer.snapshot)

        reader.newToIslam = false
        XCTAssertFalse(AppSettings(defaults: defaults).newToIslam)
        XCTAssertTrue(AppSettings(defaults: defaults).privateReminders)
    }

    func testPrivateRemindersChangeTheSnapshotSoAlertsAreRescheduled() {
        let settings = AppSettings(defaults: defaults)
        let before = settings.snapshot
        settings.privateReminders = true
        XCTAssertNotEqual(settings.snapshot, before)
    }

    func testStoredNonBoolValuesFallBackToOff() {
        defaults.set("yes", forKey: AppSettings.Keys.newToIslam)
        defaults.set("yes", forKey: AppSettings.Keys.privateReminders)
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.newToIslam)
        XCTAssertFalse(settings.privateReminders)
    }

    func testNotSureLineIsPlain() {
        XCTAssertEqual(SettingsView.notSureNote, "If you are not sure, keep this and ask your mosque.")
        XCTAssertFalse(SettingsView.notSureNote.contains("\u{2014}"))
    }

    // MARK: - Match your mosque

    private func fixedDate(in zone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
    }

    func testOneRowPerMethodInSettingsOrderWithTheCurrentOneMarked() throws {
        let place = Place.makkahFallback
        let date = try fixedDate(in: place.timeZone)
        let rows = MosqueMatchRow.rows(
            service: PrayerTimesService(),
            place: place,
            on: date,
            current: .ummAlQura,
            asrRule: .standard
        )

        XCTAssertEqual(rows.map(\.method), PrayerCalculationMethod.allCases)
        XCTAssertEqual(rows.filter(\.isCurrent).map(\.method), [.ummAlQura])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)

        let calendar = place.calendar
        for row in rows {
            XCTAssertLessThan(row.fajr, row.isha, "\(row.method) Fajr should come before Isha")
            XCTAssertTrue(calendar.isDate(row.fajr, inSameDayAs: date), "\(row.method) Fajr is not on the day")
            XCTAssertTrue(calendar.isDate(row.isha, inSameDayAs: date), "\(row.method) Isha is not on the day")
        }
    }

    func testRowsMatchWhatTodayComputesForEachMethod() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let place = Place(coordinate: Coordinate(latitude: 40.2, longitude: -74.07), timeZone: zone, isFallback: false)
        let date = try fixedDate(in: zone)
        let base = PrayerTimesService(timeZone: try XCTUnwrap(TimeZone(identifier: "UTC")))
        let rows = MosqueMatchRow.rows(service: base, place: place, on: date, current: .northAmerica, asrRule: .hanafi)

        XCTAssertEqual(rows.count, PrayerCalculationMethod.allCases.count)
        XCTAssertEqual(rows.filter(\.isCurrent).map(\.method), [.northAmerica])
        for row in rows {
            let day = try XCTUnwrap(
                base.applying(method: row.method, asrRule: .hanafi).prayerDay(for: place, on: date)
            )
            XCTAssertEqual(row.fajr, day.fajr, "\(row.method) Fajr differs from Today's")
            XCTAssertEqual(row.isha, day.isha, "\(row.method) Isha differs from Today's")
            XCTAssertLessThan(row.fajr, row.isha)
        }
        // The point of the screen: methods do not all agree.
        XCTAssertGreaterThan(Set(rows.map(\.fajr)).count, 1)
        XCTAssertGreaterThan(Set(rows.map(\.isha)).count, 1)
    }

    func testTheMarkFollowsTheChosenMethod() throws {
        let place = Place.makkahFallback
        let date = try fixedDate(in: place.timeZone)
        for method in PrayerCalculationMethod.allCases {
            let rows = MosqueMatchRow.rows(
                service: PrayerTimesService(),
                place: place,
                on: date,
                current: method,
                asrRule: .standard
            )
            XCTAssertEqual(rows.filter(\.isCurrent).map(\.method), [method])
        }
    }
}
