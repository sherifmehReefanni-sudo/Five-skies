import XCTest

final class DayViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDayViewScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "dhuhr"]
        app.launch()

        let open = app.buttons["openDayView"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "Day view button on Today did not appear")
        open.tap()

        let title = app.descendants(matching: .any)["dayViewTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Day view did not appear")
        XCTAssertTrue(
            app.descendants(matching: .any)["dayRow-fajr"].waitForExistence(timeout: 10),
            "Prayer rows did not appear"
        )
        attachScreenshot(named: "day-view")

        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["dayHijriStepper"].waitForExistence(timeout: 10),
            "Day settings did not appear"
        )
        attachScreenshot(named: "day-view-lower")

        let todayTitle = title.label
        let next = app.buttons["dayNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Next day button did not appear")
        next.tap()
        waitForLabel(differentFrom: todayTitle, on: title)
        XCTAssertTrue(app.buttons["dayToday"].waitForExistence(timeout: 10), "Today button did not appear")
        attachScreenshot(named: "day-view-next")
    }

    @MainActor
    private func waitForLabel(differentFrom label: String, on element: XCUIElement) {
        let predicate = NSPredicate(format: "label != %@", label)
        let changed = expectation(for: predicate, evaluatedWith: element)
        wait(for: [changed], timeout: 10)
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
