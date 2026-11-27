import XCTest

final class TrustUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPreferencesScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()

        let tile = app.buttons["moreTile-preferences"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Settings and backup tile did not appear")
        scrollUntilHittable(app, tile)
        tile.tap()

        let title = app.descendants(matching: .any)["preferencesTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Settings and backup screen did not appear")
        XCTAssertTrue(app.buttons["backupNow"].waitForExistence(timeout: 5), "Back up button did not appear")
        attachScreenshot(named: "preferences")

        let whatsNew = app.buttons["preferencesWhatsNew"]
        XCTAssertTrue(whatsNew.waitForExistence(timeout: 5), "What's new row did not appear")
        scrollUntilHittable(app, whatsNew)
        attachScreenshot(named: "preferences-lower")
        whatsNew.tap()
        let whatsNewTitle = app.descendants(matching: .any)["whatsNewTitle"]
        XCTAssertTrue(whatsNewTitle.waitForExistence(timeout: 10), "What's new sheet did not appear")
        attachScreenshot(named: "whats-new")
        let done = app.buttons["whatsNewDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "What's new close button did not appear")
        scrollUntilHittable(app, done)
        done.tap()

        let mission = app.buttons["preferencesMission"]
        XCTAssertTrue(mission.waitForExistence(timeout: 10), "Mission row did not appear")
        scrollUntilHittable(app, mission)
        mission.tap()
        let missionTitle = app.descendants(matching: .any)["missionTitle"]
        XCTAssertTrue(missionTitle.waitForExistence(timeout: 10), "Mission page did not appear")
        attachScreenshot(named: "mission")
    }

    @MainActor
    private func scrollUntilHittable(_ app: XCUIApplication, _ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
