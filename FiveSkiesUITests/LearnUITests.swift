import XCTest

/// The Learn tab and Memorize, which moved here from More in round E3.
final class LearnUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMemorizeOpensFromLearn() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let learnTab = app.tabBars.buttons["Learn"]
        XCTAssertTrue(learnTab.waitForExistence(timeout: 20), "The Learn tab did not appear")
        learnTab.tap()

        let memorize = app.buttons["learnOpenMemorize"]
        XCTAssertTrue(memorize.waitForExistence(timeout: 20), "The Memorize card did not appear")
        memorize.tap()
        let firstSura = app.buttons["memorizeSura-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 30), "The sura list did not load")
        firstSura.tap()
        let start = app.buttons["memorizeStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "Start button did not appear")
        start.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["memorizePracticeTitle"].waitForExistence(timeout: 15),
            "Practice screen did not appear"
        )
        XCTAssertTrue(app.buttons["memorizeKnown"].waitForExistence(timeout: 15), "Practice controls did not appear")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "memorize"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
