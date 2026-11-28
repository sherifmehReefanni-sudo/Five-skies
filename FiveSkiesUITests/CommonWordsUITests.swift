import XCTest

/// Round E3, plan L4: common words from the Learn tab, with fake word meanings (`-FSFakeWords`).
final class CommonWordsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCommonWordsScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSFakeWords"]
        app.launch()

        let learnTab = app.tabBars.buttons["Learn"]
        XCTAssertTrue(learnTab.waitForExistence(timeout: 20), "Learn tab button did not appear")
        learnTab.tap()

        let openWords = app.descendants(matching: .any).matching(identifier: "learnOpenWords").firstMatch
        XCTAssertTrue(openWords.waitForExistence(timeout: 20), "The Learn tab has no common words link")
        openWords.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "commonWords").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 30), "The common words screen did not open")

        // The index is counted from the full bundled text on first open.
        let firstWord = app.buttons.matching(identifier: "commonWord-1").firstMatch
        XCTAssertTrue(firstWord.waitForExistence(timeout: 30), "The common words were not counted")

        let headline = app.staticTexts.matching(identifier: "commonWordsHeadline").firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 5), "The headline did not appear")

        let listShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listShot.name = "common-words"
        listShot.lifetime = .keepAlways
        add(listShot)

        firstWord.tap()

        let detail = app.descendants(matching: .any).matching(identifier: "commonWordDetail").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "The word sheet did not open")

        let open = app.buttons.matching(identifier: "commonWordOpen").firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "The word sheet has no Open in the Quran button")

        // Wait for the meaning area to settle (fake data answers at once) so the screenshot is not mid load.
        let loading = app.descendants(matching: .any).matching(identifier: "commonWordLoading").firstMatch
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 10), .completed, "The meaning did not load")

        let detailShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailShot.name = "common-word-detail"
        detailShot.lifetime = .keepAlways
        add(detailShot)
    }
}
