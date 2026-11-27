import XCTest

/// The Listen tab with fake reciters and a simulated player (`-FSFakeListen`): no network, no audio.
final class ListenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testListenTabPlaysASurahAndOpensThePlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FSFixedPhase", "isha", "-FSFakeListen"]
        app.launch()

        let tab = app.tabBars.buttons["Listen"]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Listen tab button did not appear")
        tab.tap()

        XCTAssertTrue(app.staticTexts["listenTitle"].waitForExistence(timeout: 20), "Listen screen did not appear")
        XCTAssertTrue(app.buttons["listenReciterButton"].waitForExistence(timeout: 20), "The fake reciters did not load")
        let firstSurah = app.buttons["listenSurah-1"]
        XCTAssertTrue(firstSurah.waitForExistence(timeout: 20), "The surah list did not load")
        attachScreenshot(named: "listen")

        firstSurah.tap()
        let bar = app.descendants(matching: .any)["nowPlayingBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 20), "The now playing bar did not appear")
        attachScreenshot(named: "listen-playing")

        let open = app.buttons["nowPlayingOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "The now playing bar has no open button")
        open.tap()
        XCTAssertTrue(app.buttons["playerPlayPause"].waitForExistence(timeout: 20), "The player sheet did not open")
        XCTAssertTrue(app.descendants(matching: .any)["playerCredit"].exists, "The credit line is missing from the player")
        attachScreenshot(named: "listen-player")
        app.terminate()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
