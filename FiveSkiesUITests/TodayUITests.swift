import XCTest

final class TodayUITests: XCTestCase {
    private let phases = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testScreenshotOfEachSky() throws {
        for phase in phases {
            let app = launchApp(phase: phase)
            XCTAssertTrue(
                app.staticTexts["nextPrayerName"].waitForExistence(timeout: 20),
                "Today screen did not appear for \(phase)"
            )
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "today-\(phase)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    @MainActor
    func testTappingATileMarksItAsPrayed() throws {
        let app = launchApp(phase: "dhuhr")
        let tile = app.buttons["tile-asr"]
        XCTAssertTrue(tile.waitForExistence(timeout: 20), "Asr tile did not appear")

        if tile.label.hasPrefix("Unmark") {
            tile.tap()
            waitForLabel("Mark Asr as prayed", on: tile)
        }
        XCTAssertEqual(tile.label, "Mark Asr as prayed")

        tile.tap()
        waitForLabel("Unmark Asr as prayed", on: tile)

        tile.tap()
        waitForLabel("Mark Asr as prayed", on: tile)
    }

    @MainActor
    private func launchApp(phase: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", phase]
        app.launch()
        return app
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) {
        let predicate = NSPredicate(format: "label == %@", label)
        let labelMatches = expectation(for: predicate, evaluatedWith: element)
        wait(for: [labelMatches], timeout: 10)
    }
}
