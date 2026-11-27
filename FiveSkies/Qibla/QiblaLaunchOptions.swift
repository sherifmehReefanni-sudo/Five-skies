import Foundation

/// Testing hooks read only by the Qibla tab.
/// `-FSFixedHeading <degrees>` reports that device heading and never starts compass updates.
/// `-FSFixedCoordinate <lat>,<lon>` uses that coordinate for the Qibla tab and skips location.
/// `-FSQiblaLocating` holds the tab in its "finding your location" state, for screenshots.
struct QiblaLaunchOptions {
    static let fixedHeadingArgument = "-FSFixedHeading"
    static let fixedCoordinateArgument = "-FSFixedCoordinate"
    static let locatingArgument = "-FSQiblaLocating"

    let fixedHeading: Double?
    let fixedCoordinate: Coordinate?
    let forcesLocating: Bool

    init(processInfo: ProcessInfo = .processInfo) {
        let arguments = processInfo.arguments
        fixedHeading = Self.value(after: Self.fixedHeadingArgument, in: arguments)
            .flatMap(Self.parseHeading)
        fixedCoordinate = Self.value(after: Self.fixedCoordinateArgument, in: arguments)
            .flatMap(Self.parseCoordinate)
        forcesLocating = arguments.contains(Self.locatingArgument)
    }

    /// A finite heading in degrees, normalised to 0..<360.
    static func parseHeading(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value.isFinite else {
            return nil
        }
        return QiblaGuidance.normalized(value)
    }

    /// "lat,lon" in degrees, with latitude in -90...90 and longitude in -180...180.
    static func parseCoordinate(_ text: String) -> Coordinate? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude)
        else {
            return nil
        }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func value(after argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
