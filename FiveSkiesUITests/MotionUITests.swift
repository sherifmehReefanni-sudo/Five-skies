import XCTest

/// Captures short bursts of frames with motion forced on, so the living sky can be reviewed.
final class MotionUITests: XCTestCase {
    private let frameCount = 8
    private let frameInterval: TimeInterval = 0.4

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMotionFramesForIshaAndMaghrib() throws {
        for phase in ["isha", "maghrib"] {
            let app = XCUIApplication()
            app.launchArguments = ["-FSFixedPhase", phase, "-FSAnimate"]
            app.launch()
            XCTAssertTrue(
                app.staticTexts["nextPrayerName"].waitForExistence(timeout: 20),
                "Today screen did not appear for \(phase)"
            )
            for frame in 1...frameCount {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "motion-\(phase)-\(frame)"
                attachment.lifetime = .keepAlways
                add(attachment)
                if frame < frameCount {
                    Thread.sleep(forTimeInterval: frameInterval)
                }
            }
            app.terminate()
        }
    }
}
