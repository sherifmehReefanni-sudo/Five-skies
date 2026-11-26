import Adhan
import Foundation

/// The Qibla bearing from the Adhan library. No great circle math is done here.
/// Kept in its own file without SwiftUI so library names cannot clash with SwiftUI names.
enum QiblaBearing {
    /// Degrees clockwise from true north toward the Kaaba.
    static func degrees(from coordinate: Coordinate) -> Double {
        let coordinates = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return Qibla(coordinates: coordinates).direction
    }
}
