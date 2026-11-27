import XCTest

final class WidgetGalleryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Every family on one scrolling page ("widgets"), then the Lock Screen row ("widgets-lock")
    /// and the large widget ("widgets-large") each on a page of their own, so no shot depends
    /// on how far a swipe scrolls.
    @MainActor
    func testScreenshotOfWidgetGallery() throws {
        capture(page: nil, section: "widgetGalleryHome", name: "widgets")
        capture(page: "lock", section: "widgetGalleryLock", name: "widgets-lock")
        capture(page: "large", section: "widgetGalleryLarge", name: "widgets-large")
    }

    @MainActor
    private func capture(page: String?, section: String, name: String) {
        let app = XCUIApplication()
        var arguments = ["-FSFixedPhase", "maghrib", "-FSWidgetGallery"]
        if let page = page {
            arguments += ["-FSWidgetGalleryPage", page]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["widgetGallery"].waitForExistence(timeout: 20),
            "Widget gallery did not appear for \(name)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[section].waitForExistence(timeout: 5),
            "Section \(section) did not appear for \(name)"
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }
}
