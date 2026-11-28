import XCTest

/// Round E2.2: the Words sheet from the ayah toolbar, with fake word data (`-FSFakeWords`).
final class AyahWordsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWordsSheetScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSFakeWords"]
        app.launch()

        let quranTab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(quranTab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        quranTab.tap()

        let firstSura = app.buttons["suraRow-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
        firstSura.tap()

        let ayah = app.buttons["ayah-1"]
        XCTAssertTrue(ayah.waitForExistence(timeout: 20), "Ayah 1 did not appear")
        ayah.tap()

        let words = app.buttons.matching(identifier: "toolbarWords").firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 10), "The ayah toolbar has no Words button")
        words.tap()

        let sheet = app.descendants(matching: .any).matching(identifier: "wordsSheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "The Words sheet did not open")

        // The fake answers at once; wait for the first row so the screenshot shows loaded words.
        let firstPlay = app.buttons.matching(identifier: "wordPlay-1").firstMatch
        XCTAssertTrue(firstPlay.waitForExistence(timeout: 15), "The words did not load")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "words-sheet"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
