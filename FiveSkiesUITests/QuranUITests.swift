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

/// Fable condition 1 (C1): the same ayah with and without a frozen word highlight, so the two
/// screenshots can be compared pixel for pixel (glyph shapes must match; only colour may differ).
final class FollowAlongHighlightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHighlightedAndPlainAyahScreenshots() throws {
        for (name, extra) in [("reader-plain", [String]()), ("reader-highlight", ["-FSHighlightWord", "1:2:2"])] {
            let app = XCUIApplication()
            app.launchArguments = ["-FSFixedPhase", "isha"] + extra
            app.launch()
            let quranTab = app.tabBars.buttons["Quran"]
            XCTAssertTrue(quranTab.waitForExistence(timeout: 20), "Quran tab button did not appear")
            quranTab.tap()
            let firstSura = app.buttons["suraRow-1"]
            XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
            firstSura.tap()
            let ayah = app.buttons["ayah-2"]
            XCTAssertTrue(ayah.waitForExistence(timeout: 20), "Ayah 2 did not appear")
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
