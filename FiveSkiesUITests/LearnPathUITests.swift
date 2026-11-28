import XCTest

/// Learn tab: the Start here path and the reading plan. `-FSPlanSample` shows a 30 day plan
/// that started 3 days ago at page 61, in a throwaway store.
final class LearnPathUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartHereAndReadingPlan() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSPlanSample"]
        app.launch()

        let learnTab = app.tabBars.buttons["Learn"]
        XCTAssertTrue(learnTab.waitForExistence(timeout: 20), "Learn tab button did not appear")
        learnTab.tap()

        let openPath = element(app, "learnOpenPath")
        XCTAssertTrue(openPath.waitForExistence(timeout: 20), "The Start here link did not appear")
        attachScreenshot(named: "learn-tab")

        bringOnScreen(app, openPath)
        openPath.tap()
        let path = element(app, "startHere")
        XCTAssertTrue(path.waitForExistence(timeout: 20), "Start here did not open")
        XCTAssertTrue(app.buttons.matching(identifier: "pathLearn-1").firstMatch.waitForExistence(timeout: 10), "The first step has no Learn button")
        XCTAssertTrue(app.buttons.matching(identifier: "pathRead-1").firstMatch.exists, "The first step has no Read button")
        attachScreenshot(named: "start-here")

        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back button did not appear")
        back.tap()

        let openPlan = element(app, "learnOpenPlan")
        XCTAssertTrue(openPlan.waitForExistence(timeout: 20), "The reading plan link did not appear")
        bringOnScreen(app, openPlan)
        openPlan.tap()
        let plan = element(app, "readingPlan")
        XCTAssertTrue(plan.waitForExistence(timeout: 20), "The reading plan did not open")
        XCTAssertTrue(app.buttons.matching(identifier: "planOpenToday").firstMatch.waitForExistence(timeout: 10), "The sample plan did not load")
        XCTAssertTrue(app.buttons.matching(identifier: "planDone").firstMatch.exists, "I read today's portion is missing")
        attachScreenshot(named: "reading-plan")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Swipes up a few times until the element can be tapped.
    @MainActor
    private func bringOnScreen(_ app: XCUIApplication, _ target: XCUIElement) {
        var swipes = 0
        while !target.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
