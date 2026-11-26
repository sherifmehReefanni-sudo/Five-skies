import XCTest

final class MoreUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMoreTabAndToolsScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()

        let trackerTile = app.buttons["moreTile-tracker"]
        XCTAssertTrue(trackerTile.waitForExistence(timeout: 10), "More grid did not appear")
        attachScreenshot(named: "more")

        openTool(app, tile: "moreTile-tracker", title: "trackerTitle", screenshot: "tracker")
        goBack(app)

        openTool(app, tile: "moreTile-tasbih", title: "tasbihTitle", screenshot: nil)
        let reset = app.buttons["tasbihReset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10), "Tasbih reset button did not appear")
        reset.tap()
        let counter = app.buttons["tasbihCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "Tasbih counter did not appear")
        waitForValue("0", on: counter)
        counter.tap()
        counter.tap()
        counter.tap()
        waitForValue("3", on: counter)
        XCTAssertEqual(counter.value as? String, "3")
        attachScreenshot(named: "tasbih")
        goBack(app)

        openTool(app, tile: "moreTile-zakat", title: "zakatTitle", screenshot: "zakat")
        goBack(app)

        openTool(app, tile: "moreTile-hijriCalendar", title: "hijriTitle", screenshot: "hijri-calendar")
        goBack(app)
    }

    @MainActor
    private func openTool(_ app: XCUIApplication, tile identifier: String, title: String, screenshot: String?) {
        let tile = app.buttons[identifier]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "\(identifier) did not appear")
        tile.tap()
        let heading = app.descendants(matching: .any)[title]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "\(title) did not appear")
        if let screenshot {
            attachScreenshot(named: screenshot)
        }
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

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
        let predicate = NSPredicate(format: "value == %@", value)
        let valueMatches = expectation(for: predicate, evaluatedWith: element)
        wait(for: [valueMatches], timeout: 10)
    }
}
