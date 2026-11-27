import XCTest

final class ListenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testListenTabExplainsWhatIsComing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha"]
        app.launch()
        let tab = app.tabBars.buttons["Listen"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Listen tab button did not appear")
        tab.tap()
        XCTAssertTrue(app.staticTexts["listenTitle"].waitForExistence(timeout: 20), "Listen screen did not appear")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "on its way")).firstMatch.exists,
            "Listen hero text missing"
        )
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "listen"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
    }
}
