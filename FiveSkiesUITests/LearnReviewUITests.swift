import XCTest

/// Learn, Review: two sample ayahs are due (`-FSReviewSample`, a throwaway defaults suite),
/// the list shows them, and the card peeks at the stored text.
final class LearnReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReviewListAndCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSReviewSample"]
        app.launch()

        let learnTab = app.tabBars.buttons["Learn"]
        XCTAssertTrue(learnTab.waitForExistence(timeout: 20), "Learn tab button did not appear")
        learnTab.tap()

        let openReview = app.buttons["learnOpenReview"]
        XCTAssertTrue(openReview.waitForExistence(timeout: 20), "The Review card is missing on Learn")
        openReview.tap()

        let title = app.descendants(matching: .any)["learnReview"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The Review screen did not open")
        let firstRow = app.buttons["reviewRow-1-1"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 20), "The sample ayah 1:1 is not due")
        XCTAssertTrue(app.buttons["reviewRow-1-2"].exists, "The sample ayah 1:2 is not due")
        let list = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        list.name = "learn-review"
        list.lifetime = .keepAlways
        add(list)

        firstRow.tap()
        let peek = app.buttons["reviewPeek"]
        XCTAssertTrue(peek.waitForExistence(timeout: 20), "The review card did not open")
        XCTAssertTrue(app.buttons["reviewRemembered"].exists, "I remembered it is missing")
        XCTAssertTrue(app.buttons["reviewPractice"].exists, "Needs practice is missing")
        peek.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["reviewAyahText"].waitForExistence(timeout: 10),
            "Peek did not show the ayah"
        )
        let card = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        card.name = "review-card"
        card.lifetime = .keepAlways
        add(card)
    }
}
