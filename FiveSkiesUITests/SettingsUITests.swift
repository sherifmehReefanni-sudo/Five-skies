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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "settings"
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
