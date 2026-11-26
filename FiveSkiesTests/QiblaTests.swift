import XCTest
@testable import FiveSkies

final class QiblaTests: XCTestCase {
    func testNormalisationWrapsIntoZeroToThreeSixty() {
        XCTAssertEqual(QiblaGuidance.normalized(0), 0, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(360), 0, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(720), 0, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(370), 10, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(-10), 350, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(-370), 350, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(359.5), 359.5, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.normalized(.nan), 0)
        for value in stride(from: -1000.0, through: 1000.0, by: 7.3) {
            let result = QiblaGuidance.normalized(value)
            XCTAssertGreaterThanOrEqual(result, 0)
            XCTAssertLessThan(result, 360)
        }
    }

    func testSignedDifferenceTakesTheShortestRotation() {
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 20, to: 58), 38, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 58, to: 20), -38, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 10, to: 350), -20, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 0, to: 180), 180, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: 90, to: 90), 0, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.signedDifference(from: -30, to: 400), 70, accuracy: 1e-9)
        for heading in stride(from: 0.0, to: 360.0, by: 13) {
            for bearing in stride(from: 0.0, to: 360.0, by: 17) {
                let difference = QiblaGuidance.signedDifference(from: heading, to: bearing)
                XCTAssertGreaterThanOrEqual(difference, -180)
                XCTAssertLessThanOrEqual(difference, 180)
            }
        }
    }

    func testUnwrappedRotationTakesTheShortestPathAndNeverWraps() {
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: 350, to: 10), 370, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: 10, to: 350), -10, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: 20, to: 58), 58, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: 90, to: 90), 90, accuracy: 1e-9)

        // Accumulated values keep growing past 360 or shrinking below 0 without wrapping.
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: 710, to: 10), 730, accuracy: 1e-9)
        XCTAssertEqual(QiblaGuidance.unwrappedRotation(from: -350, to: 350), -370, accuracy: 1e-9)

        var clockwise = 0.0
        for step in 1...40 {
            clockwise = QiblaGuidance.unwrappedRotation(from: clockwise, to: QiblaGuidance.normalized(Double(step) * 30))
        }
        XCTAssertEqual(clockwise, 1200, accuracy: 1e-9)

        var counterclockwise = 0.0
        for step in 1...40 {
            counterclockwise = QiblaGuidance.unwrappedRotation(
                from: counterclockwise,
                to: QiblaGuidance.normalized(Double(-step) * 30)
            )
        }
        XCTAssertEqual(counterclockwise, -1200, accuracy: 1e-9)

        // Every move is at most half a turn and lands on the target angle.
        for current in stride(from: -1000.0, through: 1000.0, by: 37.3) {
            for target in stride(from: 0.0, to: 360.0, by: 23) {
                let next = QiblaGuidance.unwrappedRotation(from: current, to: target)
                XCTAssertLessThanOrEqual(abs(next - current), 180 + 1e-9)
                XCTAssertEqual(QiblaGuidance.signedDifference(from: next, to: target), 0, accuracy: 1e-6)
            }
        }
    }

    func testMotionPolicy() {
        XCTAssertTrue(MotionPolicy.isEnabled(reduceMotion: false, isFixedPhase: false, forcesAnimation: false))
        XCTAssertFalse(MotionPolicy.isEnabled(reduceMotion: true, isFixedPhase: false, forcesAnimation: false))
        XCTAssertFalse(MotionPolicy.isEnabled(reduceMotion: false, isFixedPhase: true, forcesAnimation: false))
        XCTAssertTrue(MotionPolicy.isEnabled(reduceMotion: false, isFixedPhase: true, forcesAnimation: true))
        XCTAssertFalse(MotionPolicy.isEnabled(reduceMotion: true, isFixedPhase: true, forcesAnimation: true))
    }

    func testGuidanceStates() {
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 20), .turnRight)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 100), .turnLeft)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 58), .aligned)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 53), .aligned)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 63), .aligned)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: 52.9), .turnRight)
        XCTAssertEqual(QiblaGuidance.state(bearing: 2, heading: 358), .aligned)
        XCTAssertEqual(QiblaGuidance.state(bearing: 10, heading: 350), .turnRight)
        XCTAssertEqual(QiblaGuidance.state(bearing: 350, heading: 10), .turnLeft)
        XCTAssertEqual(QiblaGuidance.state(bearing: 58, heading: nil), .noCompass(bearing: 58))
        XCTAssertEqual(QiblaGuidance.state(bearing: nil, heading: 20), .needsLocation)
    }

    func testGuidanceText() {
        XCTAssertEqual(QiblaGuidance.State.aligned.text, "You are facing the Qibla")
        XCTAssertEqual(QiblaGuidance.State.turnRight.text, "Turn right")
        XCTAssertEqual(QiblaGuidance.State.turnLeft.text, "Turn left")
        XCTAssertEqual(
            QiblaGuidance.State.noCompass(bearing: 58.4).text,
            "Compass not available on this device. Face 58° from north."
        )
        XCTAssertEqual(QiblaGuidance.State.needsLocation.text, "Qibla direction needs your location")
    }

    func testEightPointAbbreviationBoundaries() {
        let cases: [(Double, String)] = [
            (0, "N"), (22.49, "N"), (22.5, "NE"), (45, "NE"), (67.49, "NE"),
            (67.5, "E"), (112.49, "E"), (112.5, "SE"), (157.5, "S"), (202.5, "SW"),
            (247.5, "W"), (292.5, "NW"), (337.49, "NW"), (337.5, "N"), (359.9, "N"),
            (-10, "N"), (-45, "NW")
        ]
        for (bearing, expected) in cases {
            XCTAssertEqual(QiblaGuidance.compassAbbreviation(bearing), expected, "bearing \(bearing)")
        }
        XCTAssertEqual(QiblaGuidance.compassName(58), "north east")
    }

    func testBearingText() {
        XCTAssertEqual(QiblaGuidance.bearingText(58.48), "58° NE")
        XCTAssertEqual(QiblaGuidance.bearingText(359.7), "0° N")
        XCTAssertEqual(QiblaGuidance.bearingText(180), "180° S")
    }

    func testLaunchArgumentParsing() {
        XCTAssertEqual(
            QiblaLaunchOptions.parseCoordinate("40.7128,-74.0060"),
            Coordinate(latitude: 40.7128, longitude: -74.0060)
        )
        XCTAssertNil(QiblaLaunchOptions.parseCoordinate("40.7128"))
        XCTAssertNil(QiblaLaunchOptions.parseCoordinate("95,10"))
        XCTAssertNil(QiblaLaunchOptions.parseCoordinate("abc,def"))
        XCTAssertEqual(QiblaLaunchOptions.parseHeading("20"), 20)
        XCTAssertEqual(QiblaLaunchOptions.parseHeading("-90"), 270)
        XCTAssertNil(QiblaLaunchOptions.parseHeading("north"))
    }

    func testLibraryQiblaForNewYorkCity() {
        let bearing = QiblaBearing.degrees(from: Coordinate(latitude: 40.7128, longitude: -74.0060))
        XCTAssertEqual(bearing, 58.5, accuracy: 1.5)
    }
}
