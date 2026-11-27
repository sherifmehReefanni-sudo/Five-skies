import XCTest

final class QiblaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNewYorkScreenshotAsksToTurnRight() throws {
        let app = launchQibla(heading: "20")
        XCTAssertTrue(guidance("Turn right", in: app).waitForExistence(timeout: 10), "Turn right guidance missing")
        attachScreenshot(named: "qibla-newyork")
        app.terminate()
    }

    @MainActor
    func testFacingTheQiblaWhenHeadingMatchesBearing() throws {
        let app = launchQibla(heading: "58")
        XCTAssertTrue(
            guidance("You are facing the Qibla", in: app).waitForExistence(timeout: 10),
            "Aligned guidance missing"
        )
        attachScreenshot(named: "qibla-aligned")
        app.terminate()
    }

    @MainActor
    func testLocatingStateShowsBeforeAnyDirection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "dhuhr", "-FSQiblaLocating"]
        app.launch()
        let tab = app.tabBars.buttons["Qibla"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Qibla tab button did not appear")
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["qiblaLocating"].waitForExistence(timeout: 20),
            "Locating state did not appear"
        )
        XCTAssertFalse(app.staticTexts["qiblaBearing"].exists, "No direction is shown while locating")
        attachScreenshot(named: "qibla-locating")
        app.terminate()
    }

    @MainActor
    private func launchQibla(heading: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-FSFixedPhase", "asr",
            "-FSFixedCoordinate", "40.7128,-74.0060",
            "-FSFixedHeading", heading
        ]
        app.launch()
        let tab = app.tabBars.buttons["Qibla"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Qibla tab button did not appear")
        tab.tap()
        XCTAssertTrue(app.staticTexts["qiblaTitle"].waitForExistence(timeout: 20), "Qibla screen did not appear")
        return app
    }

    @MainActor
    private func guidance(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
