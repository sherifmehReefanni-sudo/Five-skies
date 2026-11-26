import Foundation

/// A coordinate paired with the time zone its prayer times are shown in.
struct Place: Equatable {
    let coordinate: Coordinate
    let timeZone: TimeZone
    /// True for the labelled Makkah fallback used when the device location is unknown.
    let isFallback: Bool

    /// Makkah, shown in Makkah's own time zone. The device zone is used only if that zone is missing.
    static let makkahFallback = Place(
        coordinate: .makkah,
        timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .current,
        isFallback: true
    )

    /// The device's own location, shown in the device time zone.
    static func device(_ coordinate: Coordinate) -> Place {
        Place(coordinate: coordinate, timeZone: .current, isFallback: false)
    }

    /// A Gregorian calendar in this place's time zone, for deciding which day it is there.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
