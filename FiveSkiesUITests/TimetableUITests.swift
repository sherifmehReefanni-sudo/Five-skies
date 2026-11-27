import XCTest

final class TimetableUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTimetableScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "dhuhr"]
        app.launch()

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 20), "More tab button did not appear")
        moreTab.tap()

        XCTAssertTrue(app.buttons["moreTile-tracker"].waitForExistence(timeout: 10), "More grid did not appear")
        let tile = app.buttons["moreTile-timetable"]
        var swipes = 0
        while !(tile.exists && tile.isHittable) && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Timetable tile did not appear")
        tile.tap()

        let title = app.descendants(matching: .any)["timetableTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Timetable screen did not open")
        let table = app.descendants(matching: .any)["timetableTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 20), "Timetable did not appear")
        XCTAssertTrue(app.buttons["timetableExport"].waitForExistence(timeout: 5), "Export button did not appear")
        attachScreenshot(named: "timetable")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
