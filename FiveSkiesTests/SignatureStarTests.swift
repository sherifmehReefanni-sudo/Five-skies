import XCTest
import SwiftUI
@testable import FiveSkies

final class SignatureStarTests: XCTestCase {
    /// A clock the test moves by hand.
    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    private func makeController() -> (SignatureStarController, TestClock) {
        let clock = TestClock()
        return (SignatureStarController(now: { clock.date }), clock)
    }

    private func sample(_ phase: Prayer, _ context: String = "fallback|isna|standard") -> SkyPhaseSample {
        SkyPhaseSample(phase: phase, context: context)
    }

    // MARK: - Opening the app

    func testPlaysOnceWhenTheAppFirstOpens() {
        let (controller, clock) = makeController()
        controller.appBecameActive()
        XCTAssertEqual(controller.playCount, 1)
        XCTAssertEqual(controller.takePending(), .appOpened)
        XCTAssertNil(controller.takePending(), "A star is handed out only once")

        clock.advance(60)
        controller.appBecameActive()
        XCTAssertEqual(controller.playCount, 1, "Becoming active again without leaving does not replay")
    }

    func testShortTripToTheBackgroundDoesNotReplay() {
        let (controller, clock) = makeController()
        controller.appBecameActive()
        clock.advance(30)
        controller.appEnteredBackground()
        clock.advance(5 * 60)
        controller.appBecameActive()
        XCTAssertEqual(controller.playCount, 1)
    }

    func testComingBackAfterALongTimeCountsAsOpening() {
        let (controller, clock) = makeController()
        controller.appBecameActive()
        _ = controller.takePending()
        clock.advance(30)
        controller.appEnteredBackground()
        clock.advance(SignatureStarRules.reopenAfter)
        controller.appBecameActive()
        XCTAssertEqual(controller.playCount, 2)
        XCTAssertEqual(controller.takePending(), .appOpened)
    }

    // MARK: - Period changes

    func testFirstSampleOnlySetsTheBaseline() {
        let (controller, _) = makeController()
        controller.observe(sample(.dhuhr))
        XCTAssertEqual(controller.playCount, 0)
    }

    func testPlaysWhenThePeriodMovesOn() {
        let (controller, clock) = makeController()
        controller.observe(sample(.dhuhr))
        clock.advance(3600)
        controller.observe(sample(.dhuhr))
        XCTAssertEqual(controller.playCount, 0, "The same phase again is not a change")
        controller.observe(sample(.asr))
        XCTAssertEqual(controller.playCount, 1)
        XCTAssertEqual(controller.takePending(), .periodChanged)
    }

    func testNewPlaceOrSettingResetsTheBaselineWithoutAStar() {
        let (controller, _) = makeController()
        controller.observe(sample(.isha, "fallback|isna|standard"))
        controller.observe(sample(.maghrib, "40.71,-74.01|isna|standard"))
        XCTAssertEqual(controller.playCount, 0, "Finding the real location is not a period change")
        controller.observe(sample(.asr, "40.71,-74.01|mwl|standard"))
        XCTAssertEqual(controller.playCount, 0, "Changing the method is not a period change")
    }

    // MARK: - Marking a prayer and the cooldown

    func testMarkingAPrayerPlaysButNotTwiceInQuickSuccession() {
        let (controller, clock) = makeController()
        controller.prayerMarked()
        XCTAssertEqual(controller.playCount, 1)
        clock.advance(2)
        controller.prayerMarked()
        XCTAssertEqual(controller.playCount, 1, "Within the cooldown the second tap gets no star")
        clock.advance(SignatureStarRules.cooldown)
        controller.prayerMarked()
        XCTAssertEqual(controller.playCount, 2)
        XCTAssertEqual(controller.takePending(), .prayerMarked)
    }

    func testAStarNotShownForTooLongIsDropped() {
        let (controller, clock) = makeController()
        controller.prayerMarked()
        clock.advance(SignatureStarRules.pendingLifetime + 1)
        XCTAssertNil(controller.takePending())
    }

    // MARK: - Drawing

    func testArcStartsAndEndsOffScreenAndStaysInTheUpperSky() {
        let size = CGSize(width: 390, height: 844)
        let start = SignatureStarDrawing.point(at: 0, in: size)
        let end = SignatureStarDrawing.point(at: 1, in: size)
        XCTAssertLessThan(start.x, 0)
        XCTAssertGreaterThan(end.x, size.width)
        for step in 0...20 {
            let point = SignatureStarDrawing.point(at: Double(step) / 20, in: size)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThan(point.y, size.height * 0.35, "The star stays above the skyline and tiles")
        }
    }

    func testStrengthIsZeroOutsideTheCrossingAndFullInTheMiddle() {
        XCTAssertEqual(SignatureStarDrawing.strength(0), 0)
        XCTAssertEqual(SignatureStarDrawing.strength(1), 0)
        XCTAssertEqual(SignatureStarDrawing.strength(-0.5), 0)
        XCTAssertEqual(SignatureStarDrawing.strength(0.5), 1, accuracy: 0.0001)
        XCTAssertEqual(SignatureStarDrawing.progress(0), 0, accuracy: 0.0001)
        XCTAssertEqual(SignatureStarDrawing.progress(1), 1, accuracy: 0.0001)
    }

    // MARK: - Legibility

    func testDaySkiesGetAScrimAndNightSkiesDoNot() {
        XCTAssertGreaterThan(SkyLegibilityScrim.strength(for: .dhuhr), 0.3)
        XCTAssertGreaterThan(SkyLegibilityScrim.strength(for: .asr), 0.2)
        XCTAssertEqual(SkyLegibilityScrim.strength(for: .fajr), 0)
        XCTAssertEqual(SkyLegibilityScrim.strength(for: .maghrib), 0)
        XCTAssertEqual(SkyLegibilityScrim.strength(for: .isha), 0)
    }

    func testTabArrivalStaysUnderTheTimeLimit() {
        XCTAssertLessThan(TabArrivalModifier.duration, 0.35)
    }
}
