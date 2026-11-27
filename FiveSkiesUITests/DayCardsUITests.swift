import XCTest

final class DayCardsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Friday 28 August 2026 is 15 Rabi I 1448 (Umm al-Qura): a Friday that is also a white day.
    @MainActor
    func testDayCardsScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "dhuhr", "-FSDayCardsDate", "2026-08-28"]
        app.launch()

        let cards = app.descendants(matching: .any)["dayCards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 20), "Day cards on Today did not appear")
        XCTAssertTrue(
            app.descendants(matching: .any)["dayCard-friday"].waitForExistence(timeout: 5),
            "Friday card did not appear"
        )
        attachScreenshot(named: "day-cards")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
