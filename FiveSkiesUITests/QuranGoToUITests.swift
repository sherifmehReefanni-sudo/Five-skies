import XCTest

/// Go to from the Quran tab: type 2:255, tap Go, land in Al-Baqara at ayah 255.
final class QuranGoToUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoToAyahFromTheQuranTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let quranTab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(quranTab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        quranTab.tap()
        XCTAssertTrue(app.buttons["suraRow-1"].waitForExistence(timeout: 20), "The sura list did not load")

        let goTo = app.buttons["quranGoTo"]
        XCTAssertTrue(goTo.waitForExistence(timeout: 10), "Go to button did not appear")
        goTo.tap()

        let field = app.textFields["goToField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Go to field did not appear")
        field.tap()
        field.typeText("2:255")

        let suggestion = app.buttons["goToSuggestion-0"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "No live suggestion appeared")
        XCTAssertTrue(suggestion.label.contains("Al-Baqara, ayah 255"), "Unexpected suggestion: \(suggestion.label)")
        attachScreenshot(named: "goto-sheet")

        let go = app.buttons["goToGo"]
        XCTAssertTrue(go.waitForExistence(timeout: 10), "Go button did not appear")
        XCTAssertTrue(go.isEnabled, "Go button is not enabled")
        go.tap()

        // The reader scrolls to ayah 255, so its header may scroll away mid check.
        // Match on identifier and label together so nothing reads a vanishing element.
        XCTAssertTrue(app.buttons["ayah-255"].waitForExistence(timeout: 20), "Ayah 255 did not appear")
        let titled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'readerTitle' AND label == 'Al-Baqara'"))
            .firstMatch
        XCTAssertTrue(
            app.navigationBars["Al-Baqara"].exists || titled.exists,
            "The reader did not open at Al-Baqara"
        )
        attachScreenshot(named: "goto-reader")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
