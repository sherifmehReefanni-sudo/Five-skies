import CoreLocation
import Foundation

/// Turns the device coordinate into a city name for display, with Apple's geocoder.
/// Only the coordinate goes to Apple, and only for a place not looked up before.
/// Nothing else is sent anywhere. Names are cached in memory and in UserDefaults.
/// The Makkah fallback needs no lookup: it returns nil and screens show `fallbackName`.
actor PlaceNameProvider {
    static let shared = PlaceNameProvider()

    /// What screens show for the labelled Makkah fallback.
    static let fallbackName = "Makkah"

    /// OFF until Reef decides. The privacy page and the location prompt promise the location
    /// is never sent anywhere, and Apple's geocoder would receive the coordinate. With this off,
    /// screens show "Your location" and no lookup is made.
    static let lookupsEnabled = false

    private static let storageKey = "placeName.cache"
    private static let maxStored = 20

    private let defaults: UserDefaults
    private var cache: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cache = (defaults.dictionary(forKey: PlaceNameProvider.storageKey) as? [String: String]) ?? [:]
    }

    /// About one kilometre of rounding, so small moves reuse the cached name.
    static func cacheKey(for coordinate: Coordinate) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }

    /// The city for `place`, nil for the fallback or when the lookup fails (for example offline).
    func cityName(for place: Place) async -> String? {
        guard !place.isFallback else { return nil }
        let key = Self.cacheKey(for: place.coordinate)
        if let known = cache[key] {
            return known
        }
        guard Self.lookupsEnabled else { return nil }
        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location),
              let name = Self.name(from: placemarks.first)
        else {
            return nil
        }
        remember(name, for: key)
        return name
    }

    private func remember(_ name: String, for key: String) {
        if cache.count >= Self.maxStored {
            cache = [:]
        }
        cache[key] = name
        defaults.set(cache, forKey: Self.storageKey)
    }

    private static func name(from placemark: CLPlacemark?) -> String? {
        guard let placemark = placemark else { return nil }
        let candidates = [placemark.locality, placemark.subAdministrativeArea, placemark.administrativeArea]
        for candidate in candidates {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}
