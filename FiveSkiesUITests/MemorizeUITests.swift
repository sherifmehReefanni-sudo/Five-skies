import XCTest

/// Memorize: the ayah whose turn it is hides behind a cover; Peek shows it again.
/// The turn is frozen with `-FSMemorizeTurn 1:2`, so no audio is needed.
final class MemorizeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testYourTurnHidesTheAyahAndPeekShowsIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSMemorizeTurn", "1:2"]
        app.launch()

        let quranTab = app.tabBars.buttons["Quran"]
        XCTAssertTrue(quranTab.waitForExistence(timeout: 20), "Quran tab button did not appear")
        quranTab.tap()
        let firstSura = app.buttons["suraRow-1"]
        XCTAssertTrue(firstSura.waitForExistence(timeout: 20), "The sura list did not load")
        firstSura.tap()

        let peek = app.buttons["memorizePeek"]
        XCTAssertTrue(peek.waitForExistence(timeout: 20), "The your turn cover did not appear")
        XCTAssertTrue(app.buttons["memorizeKnown"].exists, "I know this is missing")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "memorize-turn"
        attachment.lifetime = .keepAlways
        add(attachment)

        peek.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: peek)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Peek did not show the ayah")
        XCTAssertTrue(app.buttons["ayah-2"].exists, "Ayah 2 is not back after peeking")
    }
}
