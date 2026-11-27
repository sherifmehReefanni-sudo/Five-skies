import XCTest

final class GoalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGoalsAndTasbihStatsScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()

        // Goals: create one goal from a template.
        openTool(app, tile: "moreTile-goals", title: "goalsTitle")
        let add = app.buttons["goalsAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add a goal button did not appear")
        scrollUntilHittable(add, in: app)
        add.tap()

        let template = app.buttons["goalTemplate-allFiveDays"]
        XCTAssertTrue(template.waitForExistence(timeout: 10), "Goal templates did not appear")
        template.tap()
        let create = app.buttons["goalCreate"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "Add goal button did not appear")
        create.tap()

        let card = app.descendants(matching: .any)["goalCard-allFiveDays"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The new goal did not appear")
        let title = app.descendants(matching: .any)["goalsTitle"]
        if !title.isHittable {
            app.swipeDown()
        }
        attachScreenshot(named: "goals")
        goBack(app)

        // Tasbih: count a few times, then show today's total and the week.
        openTool(app, tile: "moreTile-tasbih", title: "tasbihTitle")
        let counter = app.buttons["tasbihCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "Tasbih counter did not appear")
        counter.tap()
        counter.tap()
        counter.tap()
        counter.tap()

        let todayTotal = app.descendants(matching: .any)["dhikrTodayTotal"]
        XCTAssertTrue(todayTotal.waitForExistence(timeout: 10), "Today's dhikr total did not appear")
        let weekTotal = app.descendants(matching: .any)["dhikrWeekTotal"]
        XCTAssertTrue(weekTotal.waitForExistence(timeout: 10), "This week's dhikr total did not appear")
        scrollUntilHittable(weekTotal, in: app)
        app.swipeUp()
        attachScreenshot(named: "tasbih-stats")
        goBack(app)
    }

    @MainActor
    private func openTool(_ app: XCUIApplication, tile identifier: String, title: String) {
        let tile = app.buttons[identifier]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "\(identifier) did not appear")
        scrollUntilHittable(tile, in: app)
        tile.tap()
        let heading = app.descendants(matching: .any)[title]
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "\(title) did not appear")
    }

    /// Swipes down to the top first (a screen may come back scrolled), then up until the
    /// element is on screen.
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !element.isHittable && swipes < 3 {
            app.swipeDown()
            swipes += 1
        }
        swipes = 0
        while !element.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is not on screen")
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back button did not appear")
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["moreTitle"].waitForExistence(timeout: 10), "Did not return to More")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
