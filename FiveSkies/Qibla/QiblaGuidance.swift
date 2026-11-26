import Foundation

/// Pure angle logic for the Qibla compass. All angles are degrees clockwise from north.
struct QiblaGuidance {
    /// How close, in degrees, the device heading must be to the bearing to count as facing it.
    static let alignmentTolerance: Double = 5

    private static let abbreviations = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    private static let spokenNames = [
        "north", "north east", "east", "south east",
        "south", "south west", "west", "north west"
    ]

    /// `degrees` wrapped into 0..<360. Non-finite input returns 0.
    static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        let wrapped = remainder < 0 ? remainder + 360 : remainder
        return wrapped >= 360 ? 0 : wrapped
    }

    /// The shortest signed rotation from `heading` to `bearing`, in -180...180.
    /// Positive means turn clockwise (right), negative means turn counterclockwise (left).
    static func signedDifference(from heading: Double, to bearing: Double) -> Double {
        let difference = normalized(bearing - heading)
        return difference > 180 ? difference - 360 : difference
    }

    /// Whether `heading` is within `alignmentTolerance` of `bearing`.
    static func isAligned(heading: Double, bearing: Double) -> Bool {
        abs(signedDifference(from: heading, to: bearing)) <= alignmentTolerance
    }

    /// The bearing rounded to whole degrees in 0..<360.
    static func wholeDegrees(_ bearing: Double) -> Int {
        Int(normalized(bearing).rounded()) % 360
    }

    /// Index into the 8 compass points, each covering 45 degrees centred on its direction.
    static func compassPointIndex(_ bearing: Double) -> Int {
        Int((normalized(bearing) + 22.5) / 45) % 8
    }

    /// The 8 point compass abbreviation, such as "NE".
    static func compassAbbreviation(_ bearing: Double) -> String {
        abbreviations[compassPointIndex(bearing)]
    }

    /// The 8 point compass direction in words, such as "north east".
    static func compassName(_ bearing: Double) -> String {
        spokenNames[compassPointIndex(bearing)]
    }

    /// Display text for the bearing, such as "58° NE".
    static func bearingText(_ bearing: Double) -> String {
        "\(wholeDegrees(bearing))° \(compassAbbreviation(bearing))"
    }

    /// Rotation for the dial (ring, ticks and letters) so north on the dial points to real north.
    static func dialRotation(heading: Double?) -> Double {
        -(heading ?? 0)
    }

    /// The next value for an accumulated, unwrapped rotation that should show `target` degrees.
    /// It moves by the shortest signed difference, so an animation never spins the long way
    /// round when the angle crosses 0 or 360, and the result can grow past 360 or below 0.
    static func unwrappedRotation(from current: Double, to target: Double) -> Double {
        guard current.isFinite else { return normalized(target) }
        return current + signedDifference(from: current, to: target)
    }

    /// Rotation for the needle relative to the top of the screen.
    static func needleRotation(bearing: Double, heading: Double?) -> Double {
        normalized(bearing - (heading ?? 0))
    }

    /// What the guidance line should say.
    enum State: Equatable {
        case needsLocation
        case noCompass(bearing: Double)
        case aligned
        case turnRight
        case turnLeft

        var text: String {
            switch self {
            case .needsLocation:
                return "Qibla direction needs your location"
            case let .noCompass(bearing):
                return "Compass not available on this device. Face \(QiblaGuidance.wholeDegrees(bearing))° from north."
            case .aligned:
                return "You are facing the Qibla"
            case .turnRight:
                return "Turn right"
            case .turnLeft:
                return "Turn left"
            }
        }
    }

    /// The guidance for a bearing (nil when the location is unknown) and a heading (nil without a compass).
    static func state(bearing: Double?, heading: Double?) -> State {
        guard let bearing = bearing else { return .needsLocation }
        guard let heading = heading else { return .noCompass(bearing: bearing) }
        if isAligned(heading: heading, bearing: bearing) { return .aligned }
        return signedDifference(from: heading, to: bearing) > 0 ? .turnRight : .turnLeft
    }
}
