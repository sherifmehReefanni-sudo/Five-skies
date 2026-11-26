import XCTest
@testable import FiveSkies

final class PrayedStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "PrayedStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testRoundTripsAcrossInstances() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let writer = PrayedStore(defaults: defaults, timeZone: utc)
        writer.setPrayed(true, .fajr, on: date)
        writer.setPrayed(true, .asr, on: date)

        let reader = PrayedStore(defaults: defaults, timeZone: utc)
        XCTAssertEqual(reader.prayers(on: date), [.fajr, .asr])

        reader.setPrayed(false, .fajr, on: date)
        XCTAssertEqual(writer.prayers(on: date), [.asr])
    }

    func testDaysAreKeptSeparate() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let nextDay = date.addingTimeInterval(24 * 3600)
        let store = PrayedStore(defaults: defaults, timeZone: utc)
        store.setPrayed(true, .isha, on: date)

        XCTAssertEqual(store.prayers(on: nextDay), [])
        XCTAssertEqual(store.dayKey(for: date), "2027-01-15")
    }
}
