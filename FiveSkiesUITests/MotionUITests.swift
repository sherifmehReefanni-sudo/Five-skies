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

    /// The signature star frozen at points of its crossing, on a night sky and a bright one.
    /// Live frames cannot be timed reliably on CI, so the look is checked this way.
    @MainActor
    func testSignatureStarFrozenFrames() throws {
        let frames: [(phase: String, share: String)] = [
            ("isha", "0.3"), ("isha", "0.55"), ("isha", "0.85"), ("dhuhr", "0.55"), ("maghrib", "0.55")
        ]
        for frame in frames {
            let app = XCUIApplication()
            app.launchArguments = ["-FSFixedPhase", frame.phase, "-FSStarFrame", frame.share]
            app.launch()
            XCTAssertTrue(
                app.staticTexts["nextPrayerName"].waitForExistence(timeout: 20),
                "Today screen did not appear for \(frame.phase)"
            )
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "star-\(frame.phase)-\(frame.share)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
