import XCTest
@testable import FiveSkies

final class ReadingSettingsTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "ReadingSettingsTests.\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    @MainActor
    func testKeysAreStable() {
        XCTAssertEqual(ReadingPreferences.showsTranslationKey, "reading.showsTranslation")
        XCTAssertEqual(ReadingPreferences.backgroundKey, "reading.background")
        // The size keeps the reader's existing key and range, so saved sizes carry over.
        XCTAssertEqual(ReadingPreferences.textSizeKey, SurahReaderView.textSizeKey)
        XCTAssertEqual(ReadingPreferences.textSizeRange, SurahReaderView.textSizeRange)
        XCTAssertEqual(ReadingPreferences.defaultTextSize, SurahReaderView.defaultTextSize)
    }

    func testDefaults() throws {
        let prefs = ReadingPreferences(defaults: try makeDefaults())
        XCTAssertTrue(prefs.showsTranslation, "Meaning shows by default once a translation is downloaded")
        XCTAssertEqual(prefs.background, .sky)
        XCTAssertEqual(prefs.textSize, 30)
    }

    func testShowsTranslationPersists() throws {
        let defaults = try makeDefaults()
        let prefs = ReadingPreferences(defaults: defaults)
        prefs.showsTranslation = false
        XCTAssertFalse(ReadingPreferences(defaults: defaults).showsTranslation)
        XCTAssertEqual(defaults.object(forKey: "reading.showsTranslation") as? Bool, false)

        prefs.showsTranslation = true
        XCTAssertTrue(ReadingPreferences(defaults: defaults).showsTranslation)
    }

    func testBackgroundChoicePersists() throws {
        let defaults = try makeDefaults()
        let prefs = ReadingPreferences(defaults: defaults)

        prefs.background = .plainDark
        XCTAssertEqual(ReadingPreferences(defaults: defaults).background, .plainDark)
        XCTAssertEqual(defaults.string(forKey: "reading.background"), "plainDark")

        prefs.background = .sky
        XCTAssertEqual(ReadingPreferences(defaults: defaults).background, .sky)
        XCTAssertEqual(defaults.string(forKey: "reading.background"), "sky")
    }

    func testUnknownBackgroundFallsBackToSky() throws {
        let defaults = try makeDefaults()
        defaults.set("sepia", forKey: ReadingPreferences.backgroundKey)
        XCTAssertEqual(ReadingPreferences(defaults: defaults).background, .sky)
    }

    func testBackgroundOptions() {
        XCTAssertEqual(QuranBackground.allCases, [.sky, .plainDark])
        XCTAssertEqual(QuranBackground.sky.rawValue, "sky")
        XCTAssertEqual(QuranBackground.plainDark.rawValue, "plainDark")
        XCTAssertEqual(QuranBackground.sky.title, "Sky")
        XCTAssertEqual(QuranBackground.plainDark.title, "Plain dark")
        XCTAssertEqual(QuranBackground(rawValue: "plainDark"), .plainDark)
    }

    func testTextSizePersistsAndClamps() throws {
        let defaults = try makeDefaults()
        let prefs = ReadingPreferences(defaults: defaults)

        prefs.textSize = 36
        XCTAssertEqual(ReadingPreferences(defaults: defaults).textSize, 36)
        XCTAssertEqual(defaults.double(forKey: "quranArabicTextSize"), 36)

        prefs.textSize = 100
        XCTAssertEqual(prefs.textSize, 44)
        XCTAssertEqual(defaults.double(forKey: "quranArabicTextSize"), 44)

        defaults.set(5.0, forKey: "quranArabicTextSize")
        XCTAssertEqual(prefs.textSize, 22)
    }
}
