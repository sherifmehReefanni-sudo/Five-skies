import XCTest

final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpensSettingsFromToday() throws {
        let app = launchApp(phase: "isha")
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "Settings button did not appear")
        gear.tap()

        XCTAssertTrue(
            app.staticTexts["Adhan and alerts"].waitForExistence(timeout: 10),
            "Settings screen did not appear"
        )
        attachScreenshot(named: "settings")

        // Night alarm: scroll to it, turn it on to show its options, screenshot, then turn it off again.
        let toggle = app.switches["nightAlarmToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Night alarm switch did not appear")
        var swipes = 0
        while !toggle.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.isHittable, "Night alarm switch is not on screen")

        let wasOn = Self.isOn(toggle)
        if !wasOn {
            setSwitch(toggle)
        }
        XCTAssertTrue(
            app.staticTexts["Rings on"].waitForExistence(timeout: 5),
            "Night alarm options did not appear"
        )
        if !app.staticTexts["Rings on"].isHittable {
            app.swipeUp()
        }
        attachScreenshot(named: "settings-night-alarm")

        if !wasOn, toggle.isHittable {
            setSwitch(toggle)
        }
    }

    /// Taps a switch, falling back to its right edge where the knob sits.
    @MainActor
    private func setSwitch(_ toggle: XCUIElement) {
        let before = Self.isOn(toggle)
        toggle.tap()
        if Self.isOn(toggle) == before {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    @MainActor
    private static func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchApp(phase: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", phase]
        app.launch()
        return app
    }
}
