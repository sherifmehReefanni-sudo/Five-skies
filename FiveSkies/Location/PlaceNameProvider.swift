import Foundation

/// Turns the device coordinate into a nearby city name for display, from the bundled GeoNames list.
/// No network call: the lookup runs on the device, so the location still never leaves it.
/// Returns nil (screens show "Your location") for the Makkah fallback, when no city is within 50 km,
/// or when the list is not bundled. The list loads once, lazily, on this actor (never the main thread).
actor PlaceNameProvider {
    static let shared = PlaceNameProvider()

    /// What screens show for the labelled Makkah fallback.
    static let fallbackName = "Makkah"

    private static let maxCached = 20

    private let loadIndex: @Sendable () -> CityIndex?
    private var index: CityIndex?
    private var didLoad = false
    private var cache: [String: String] = [:]

    /// `loadIndex` reads the bundled list by default; tests pass small in-memory lists.
    init(loadIndex: @escaping @Sendable () -> CityIndex? = { CityIndex.load(contentsOf: CityIndex.bundledURL()) }) {
        self.loadIndex = loadIndex
    }

    /// About one kilometre of rounding, so small moves reuse the cached name.
    static func cacheKey(for coordinate: Coordinate) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    /// "City, CC" for `place`, or nil for the fallback, when nothing is within 50 km, or when the list is missing.
    func cityName(for place: Place) async -> String? {
        guard !place.isFallback else { return nil }
        let key = Self.cacheKey(for: place.coordinate)
        if let known = cache[key] {
            return known
        }
        if !didLoad {
            didLoad = true
            index = loadIndex()
        }
        guard let city = index?.nearest(to: place.coordinate) else {
            return nil
        }
        let name = city.displayName
        if cache.count >= Self.maxCached {
            cache = [:]
        }
        cache[key] = name
        return name
    }
}
