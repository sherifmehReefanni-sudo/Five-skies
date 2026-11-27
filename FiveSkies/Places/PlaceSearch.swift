import Foundation

/// One place found near the user. A plain value: nothing from MapKit is kept.
struct PlaceResult: Identifiable, Equatable, Sendable {
    let name: String
    let coordinate: Coordinate
    /// Straight line distance from the user, in metres.
    let distance: Double
    let address: String?
    let phone: String?
    let url: URL?

    var id: String {
        "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
    }
}

/// Finds places for a natural language query around a coordinate.
protocol PlaceSearching {
    func search(query: String, near origin: Coordinate, radius: Double) async throws -> [PlaceResult]
}

/// What each places screen searches for.
enum PlaceKind: String, Sendable {
    case mosques
    case halal

    var query: String {
        switch self {
        case .mosques: return "mosque"
        case .halal: return "halal restaurant"
        }
    }

    /// The search area around the user, in metres from the centre.
    static let searchRadius: Double = 10_000
}

/// Distance maths and ordering shared by every search implementation.
enum PlaceDistance {
    static let earthRadius: Double = 6_371_000

    /// Great circle distance in metres between two coordinates.
    static func metres(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * Double.pi / 180
        let lat2 = b.latitude * Double.pi / 180
        let dLat = (b.latitude - a.latitude) * Double.pi / 180
        let dLon = (b.longitude - a.longitude) * Double.pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
        return earthRadius * c
    }

    /// Nearest first. Equal distances keep a stable order by name.
    static func sorted(_ places: [PlaceResult]) -> [PlaceResult] {
        places.sorted { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            return lhs.name < rhs.name
        }
    }
}

/// A search that answers from a fixed list, for tests and the fixed screenshot mode.
/// Distances are worked out from the coordinate the search is given.
struct FakePlaceSearch: PlaceSearching {
    struct Entry: Sendable {
        let name: String
        let coordinate: Coordinate
        let address: String?
    }

    enum FakeError: Error {
        case failed
    }

    let entries: [Entry]
    let fails: Bool

    init(entries: [Entry], fails: Bool = false) {
        self.entries = entries
        self.fails = fails
    }

    func search(query: String, near origin: Coordinate, radius: Double) async throws -> [PlaceResult] {
        if fails {
            throw FakeError.failed
        }
        let results = entries.map { entry in
            PlaceResult(
                name: entry.name,
                coordinate: entry.coordinate,
                distance: PlaceDistance.metres(from: origin, to: entry.coordinate),
                address: entry.address,
                phone: nil,
                url: nil
            )
        }
        return PlaceDistance.sorted(results)
    }

    /// The centre the screenshot samples are placed around. Not a real location of the user.
    static let sampleOrigin = Coordinate(latitude: 0, longitude: 0)

    /// Three clearly generic rows at fixed distances north of the sample origin.
    static func samples(for kind: PlaceKind) -> FakePlaceSearch {
        let stem: String
        switch kind {
        case .mosques: stem = "Sample mosque"
        case .halal: stem = "Sample restaurant"
        }
        // Listed out of order so the screenshot also shows the sorting.
        let offsets: [(Int, Double)] = [(2, 0.011), (1, 0.004), (3, 0.023)]
        let entries = offsets.map { number, latitude in
            Entry(
                name: "\(stem) \(number)",
                coordinate: Coordinate(latitude: sampleOrigin.latitude + latitude, longitude: sampleOrigin.longitude),
                address: "Sample address \(number)"
            )
        }
        return FakePlaceSearch(entries: entries)
    }
}
