import XCTest
@testable import FiveSkies

final class ThemeTests: XCTestCase {
    func testRawValuesAndDefault() {
        XCTAssertEqual(SkyTheme.living.rawValue, "living")
        XCTAssertEqual(SkyTheme.midnight.rawValue, "midnight")
        XCTAssertEqual(SkyTheme.emerald.rawValue, "emerald")
        XCTAssertEqual(SkyTheme.desert.rawValue, "desert")
        XCTAssertEqual(SkyTheme.allCases.count, 4)
        XCTAssertEqual(SkyTheme.defaultTheme, .living)
    }

    func testTitles() {
        XCTAssertEqual(SkyTheme.living.title, "Living sky")
        XCTAssertEqual(SkyTheme.desert.title, "Desert dawn")
    }

    func testOnlyLivingSkyHasNoFixedGradient() {
        XCTAssertNil(SkyTheme.living.gradient)
        XCTAssertNil(SkyStyle.style(forTheme: .living))
        for theme in SkyTheme.allCases where theme != .living {
            let gradient = theme.gradient ?? []
            XCTAssertEqual(gradient.count, 3)
            XCTAssertEqual(gradient.first?.location, 0)
            XCTAssertEqual(gradient.last?.location, 1)
            XCTAssertNotNil(SkyStyle.style(forTheme: theme))
        }
        XCTAssertEqual(SkyTheme.midnight.gradient?.map { $0.hex }, [0x03061A, 0x141E55, 0x2E2560])
        XCTAssertEqual(SkyTheme.emerald.gradient?.map { $0.hex }, [0x04201C, 0x0C5A58, 0x16907A])
        XCTAssertEqual(SkyTheme.desert.gradient?.map { $0.hex }, [0x2A1638, 0x8E5A86, 0xF0A070])
    }

    func testLaunchArgumentParsing() {
        XCTAssertEqual(SkyTheme.launchTheme(in: ["-FSTheme", "midnight"]), .midnight)
        XCTAssertEqual(SkyTheme.launchTheme(in: ["app", "-FSFixedPhase", "isha", "-FSTheme", "desert"]), .desert)
        XCTAssertEqual(SkyTheme.launchTheme(in: ["-FSTheme", "Emerald"]), .emerald)
        XCTAssertNil(SkyTheme.launchTheme(in: ["-FSTheme"]))
        XCTAssertNil(SkyTheme.launchTheme(in: ["-FSTheme", "pink"]))
        XCTAssertNil(SkyTheme.launchTheme(in: []))
    }

    func testEffectiveTheme() {
        XCTAssertEqual(SkyTheme.effective(stored: .emerald, arguments: []), .emerald)
        XCTAssertEqual(SkyTheme.effective(stored: .emerald, arguments: ["-FSFixedPhase", "isha"]), .living)
        XCTAssertEqual(
            SkyTheme.effective(stored: .emerald, arguments: ["-FSFixedPhase", "isha", "-FSTheme", "midnight"]),
            .midnight
        )
        XCTAssertEqual(
            SkyTheme.effective(stored: .desert, arguments: ["-FSFixedPhase", "isha", "-FSTheme", "pink"]),
            .living
        )
        XCTAssertEqual(SkyTheme.effective(stored: .living, arguments: ["-FSTheme", "living"]), .living)
    }

    func testThemeStoreRoundTrip() throws {
        let suite = "ThemeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ThemeStore(defaults: defaults).theme, .living)
        ThemeStore(defaults: defaults).setTheme(.emerald)
        XCTAssertEqual(ThemeStore(defaults: defaults).theme, .emerald)
        XCTAssertEqual(defaults.string(forKey: SkyTheme.storageKey), "emerald")
        XCTAssertEqual(ThemeStore(defaults: defaults).effectiveTheme(arguments: []), .emerald)
        XCTAssertEqual(ThemeStore(defaults: defaults).effectiveTheme(arguments: ["-FSFixedPhase", "fajr"]), .living)

        defaults.set("unknown", forKey: SkyTheme.storageKey)
        XCTAssertEqual(ThemeStore(defaults: defaults).theme, .living)
    }
}
