import XCTest

final class ToolsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlacesMemorizeAndTipJarScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()
        XCTAssertTrue(app.buttons["moreTile-tracker"].waitForExistence(timeout: 15), "More grid did not appear")

        // Mosques nearby, with the fixed sample rows.
        openTool(app, tile: "moreTile-mosques", title: "mosquesTitle")
        waitForAny(app, "placeRow-0", message: "Sample mosques did not appear")
        attachScreenshot(named: "mosques")
        goBackToMore(app)

        // Halal food, with the fixed sample rows.
        openTool(app, tile: "moreTile-halal", title: "halalTitle")
        waitForAny(app, "placeRow-0", message: "Sample restaurants did not appear")
        attachScreenshot(named: "halal")
        goBackToMore(app)

        // Tip jar, from the support row.
        let support = supportRow(app)
        XCTAssertTrue(support.waitForExistence(timeout: 15), "Support row did not appear")
        if !support.isHittable {
            app.swipeUp()
        }
        support.tap()
        waitForAny(app, "tipJarTitle", message: "Tip jar did not appear")
        // Wait for loading to settle on either the products or the calm unavailable message.
        let settled = NSPredicate { _, _ in
            app.descendants(matching: .any)["tipUnavailable"].exists
                || app.descendants(matching: .any)["tipMessage"].exists
        }
        let settledExpectation = expectation(for: settled, evaluatedWith: nil)
        wait(for: [settledExpectation], timeout: 30)
        attachScreenshot(named: "tip-jar")
    }

    // MARK: - Helpers

    /// The support row, by the identifier the More tab is being given, or its current one.
    @MainActor
    private func supportRow(_ app: XCUIApplication) -> XCUIElement {
        let wanted = app.buttons["supportRow"]
        if wanted.waitForExistence(timeout: 10) {
            return wanted
        }
        return app.buttons["moreSupport"]
    }

    @MainActor
    private func openTool(_ app: XCUIApplication, tile identifier: String, title: String, timeout: TimeInterval = 15) {
        let tile = app.buttons[identifier]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "\(identifier) did not appear")
        if !tile.isHittable {
            app.swipeUp()
        }
        tile.tap()
        waitForAny(app, title, timeout: timeout, message: "\(title) did not appear")
    }

    @MainActor
    private func waitForAny(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 20, message: String) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
    }

    /// Taps the back button until the More grid is showing again.
    @MainActor
    private func goBackToMore(_ app: XCUIApplication) {
        let grid = app.buttons["moreTile-tracker"]
        for _ in 0..<5 {
            if grid.waitForExistence(timeout: 2), grid.isHittable {
                return
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 10) else { break }
            back.tap()
        }
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "Did not return to More")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
