import XCTest

final class QuranUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuranListReaderSearchAndTextSizeScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let quranTab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(quranTab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        quranTab.tap()

        let firstSura = app.buttons["suraRow-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
        attachScreenshot(named: "quran-list")

        firstSura.tap()
        waitForReader(app)
        attachScreenshot(named: "quran-reader")

        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back button did not appear")
        back.tap()
        XCTAssertTrue(app.buttons["suraRow-1"].waitForExistence(timeout: 10), "Did not return to the sura list")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field did not appear")
        search.tap()
        search.typeText("Kahf")

        let kahf = app.buttons["suraRow-18"]
        XCTAssertTrue(kahf.waitForExistence(timeout: 10), "Al-Kahf did not appear in the search results")
        kahf.tap()
        waitForReader(app)
        let title = app.descendants(matching: .any)["readerTitle"]
        XCTAssertEqual(title.label, "Al-Kahf")
        attachScreenshot(named: "quran-reader-kahf")

        let textSize = app.buttons["readerTextSize"]
        XCTAssertTrue(textSize.waitForExistence(timeout: 10), "Text size button did not appear")
        textSize.tap()
        let slider = app.sliders["textSizeSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "Text size sheet did not appear")
        attachScreenshot(named: "quran-text-size")
    }

    @MainActor
    private func waitForReader(_ app: XCUIApplication) {
        let title = app.descendants(matching: .any)["readerTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The reader did not appear")
        XCTAssertTrue(app.buttons["ayah-1"].waitForExistence(timeout: 10), "The first ayah did not appear")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
