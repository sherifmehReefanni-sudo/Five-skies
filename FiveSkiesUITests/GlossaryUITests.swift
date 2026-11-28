import XCTest

final class GlossaryUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGlossaryFromMore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()

        let tile = app.buttons["moreTile-glossary"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Glossary tile did not appear")
        var swipes = 0
        while !tile.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        tile.tap()

        let glossary = app.descendants(matching: .any)["glossary"]
        XCTAssertTrue(glossary.waitForExistence(timeout: 10), "Glossary did not appear")
        XCTAssertTrue(app.descendants(matching: .any)["glossary-adhan"].waitForExistence(timeout: 5), "Adhan is not in the glossary")
        attachScreenshot(named: "glossary")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
