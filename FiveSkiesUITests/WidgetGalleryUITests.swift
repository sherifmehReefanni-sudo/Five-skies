import XCTest

final class WidgetGalleryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshotOfWidgetGallery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "maghrib", "-FSWidgetGallery"]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["widgetGallery"].waitForExistence(timeout: 20),
            "Widget gallery did not appear"
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "widgets"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The large widget sits below the fold on a phone screen, so it gets its own shot.
        app.swipeUp()
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let large = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        large.name = "widgets-large"
        large.lifetime = .keepAlways
        add(large)
        app.terminate()
    }
}
