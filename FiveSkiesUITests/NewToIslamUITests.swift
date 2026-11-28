import XCTest

/// Plan N1, N5 and N6 on the "Adhan and alerts" screen, opened from the gear on Today
/// (that screen holds the calculation method row). Fixed clock, Makkah fallback place.
final class NewToIslamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewToIslamSettingsAndMatchYourMosque() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "Settings button did not appear")
        gear.tap()
        XCTAssertTrue(
            app.staticTexts["Adhan and alerts"].waitForExistence(timeout: 10),
            "Settings screen did not appear"
        )

        let newToIslam = app.switches["settingsNewToIslam"]
        XCTAssertTrue(newToIslam.waitForExistence(timeout: 10), "New to Islam switch did not appear")
        let privateReminders = app.switches["settingsPrivateReminders"]
        XCTAssertTrue(privateReminders.waitForExistence(timeout: 5), "Private reminders switch did not appear")
        scrollUntilHittable(app, privateReminders)
        attachScreenshot(named: "settings-new-to-islam")

        let link = app.buttons["matchMosqueLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Match your mosque row did not appear")
        scrollUntilHittable(app, link)
        XCTAssertTrue(link.isHittable, "Match your mosque row is not on screen")
        link.tap()

        let title = app.descendants(matching: .any)["matchMosque"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Match your mosque screen did not appear")
        XCTAssertTrue(
            app.descendants(matching: .any)["matchMosqueRow-ummAlQura"].waitForExistence(timeout: 5),
            "Method rows did not appear"
        )
        // Let the push finish before the capture.
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot(named: "match-mosque")
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
