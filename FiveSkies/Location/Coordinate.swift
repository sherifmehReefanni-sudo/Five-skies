import Foundation

/// A latitude and longitude in degrees.
struct Coordinate: Equatable {
    let latitude: Double
    let longitude: Double

    /// Used when the device location is unavailable or not yet known.
    static let makkah = Coordinate(latitude: 21.4225, longitude: 39.8262)
}
