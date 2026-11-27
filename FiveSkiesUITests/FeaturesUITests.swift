import XCTest

final class FeaturesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRamadanThemesAndShareCardScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()
        XCTAssertTrue(app.buttons["moreTile-tracker"].waitForExistence(timeout: 10), "More grid did not appear")

        openTool(app, tile: "moreTile-ramadan", title: "ramadanTitle")
        XCTAssertTrue(
            app.descendants(matching: .any)["ramadanCountdown"].waitForExistence(timeout: 10),
            "Ramadan times did not appear"
        )
        attachScreenshot(named: "ramadan")
        goBack(app)

        openTool(app, tile: "moreTile-themes", title: "themesTitle")
        XCTAssertTrue(app.buttons["themeCard-living"].waitForExistence(timeout: 10), "Theme cards did not appear")
        attachScreenshot(named: "themes")
        goBack(app)

        let quranTab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(quranTab.waitForExistence(timeout: 10), "Quran tab button did not appear")
        quranTab.tap()

        let firstSura = app.buttons["suraRow-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
        firstSura.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["readerTitle"].waitForExistence(timeout: 20),
            "The reader did not appear"
        )
        let firstAyah = app.buttons["ayah-1"]
        XCTAssertTrue(firstAyah.waitForExistence(timeout: 20), "The first ayah did not appear")
        firstAyah.tap()

        let shareAsImage = app.buttons["Share as image"]
        XCTAssertTrue(shareAsImage.waitForExistence(timeout: 10), "Share as image did not appear in the ayah menu")
        shareAsImage.tap()

        let shareButton = app.buttons["shareCardShare"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 20), "The share card sheet did not appear")
        // Give the sheet time to finish its presentation before the screenshot.
        _ = app.descendants(matching: .any)["shareCardPreview"].waitForExistence(timeout: 5)
        attachScreenshot(named: "share-card")
    }

    @MainActor
    private func openTool(_ app: XCUIApplication, tile identifier: String, title: String) {
        let tile = app.buttons[identifier]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "\(identifier) did not appear")
        tile.tap()
        let heading = app.descendants(matching: .any)[title]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "\(title) did not appear")
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back button did not appear")
        back.tap()
        XCTAssertTrue(app.buttons["moreTile-tracker"].waitForExistence(timeout: 10), "Did not return to More")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
