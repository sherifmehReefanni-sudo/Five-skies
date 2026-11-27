import XCTest

/// The first-run flow in screenshot mode: every page captured, then Today.
/// `-FSShowOnboarding` shows the flow and makes every button only move on, so no permission is asked.
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFlow() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSShowOnboarding"]
        app.launch()
        return app
    }

    @MainActor
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    @MainActor
    func testFirstRunFlowPagesThenToday() throws {
        let app = launchFlow()
        for number in 1...4 {
            XCTAssertTrue(
                app.staticTexts["onboardingTitle-\(number)"].waitForExistence(timeout: 20),
                "Onboarding page \(number) did not appear"
            )
            XCTAssertTrue(app.buttons["onboardingSkip"].exists, "Skip is missing on page \(number)")
            // Let the cover finish sliding in before the first capture.
            Thread.sleep(forTimeInterval: number == 1 ? 1.0 : 0.3)
            screenshot("onboarding-\(number)")
            let button = app.buttons[number == 4 ? "onboardingDone" : "onboardingNext"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Primary button missing on page \(number)")
            button.tap()
        }
        XCTAssertTrue(waitUntilGone(app.buttons["onboardingDone"], timeout: 10), "Onboarding did not close")
        XCTAssertTrue(
            app.staticTexts["nextPrayerName"].waitForExistence(timeout: 20),
            "Today did not appear after onboarding"
        )
    }

    @MainActor
    func testSkipOpensToday() throws {
        let app = launchFlow()
        XCTAssertTrue(app.staticTexts["onboardingTitle-1"].waitForExistence(timeout: 20))
        let next = app.buttons["onboardingNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.staticTexts["onboardingTitle-2"].waitForExistence(timeout: 5))
        app.buttons["onboardingSkip"].tap()
        XCTAssertTrue(waitUntilGone(app.buttons["onboardingSkip"], timeout: 10), "Skip did not close onboarding")
        XCTAssertTrue(app.staticTexts["nextPrayerName"].waitForExistence(timeout: 20))
    }
}
