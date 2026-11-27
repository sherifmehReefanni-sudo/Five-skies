import Foundation

/// What the widgets need from the app to compute prayer times: where, in which time zone,
/// and with which calculation method and Asr rule. Compiled into the app and the widget extension.
struct SharedPrayerConfig: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var isFallback: Bool
    var calculationMethod: PrayerCalculationMethod
    var asrRule: AsrRule

    init(place: Place, calculationMethod: PrayerCalculationMethod, asrRule: AsrRule) {
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        timeZoneIdentifier = place.timeZone.identifier
        isFallback = place.isFallback
        self.calculationMethod = calculationMethod
        self.asrRule = asrRule
    }

    /// The labelled Makkah fallback with the default method and Asr rule.
    static var fallback: SharedPrayerConfig {
        SharedPrayerConfig(
            place: .makkahFallback,
            calculationMethod: AppSettings.defaultCalculationMethod,
            asrRule: AppSettings.defaultAsrRule
        )
    }

    /// The stored place. An unknown time zone identifier falls back to Makkah's zone.
    var place: Place {
        Place(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            timeZone: TimeZone(identifier: timeZoneIdentifier) ?? Place.makkahFallback.timeZone,
            isFallback: isFallback
        )
    }

    /// Whether the coordinate is a real place on Earth.
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Reads and writes `SharedPrayerConfig` as JSON in the App Group's UserDefaults.
/// When the App Group container is missing (for example in unsigned simulator builds) the suite
/// can be nil; then nothing is stored and readers get the Makkah fallback.
struct SharedPrayerConfigStore {
    static let appGroupIdentifier = "group.app.fiveskies.ios"
    static let storageKey = "widgets.sharedPrayerConfig"

    private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    /// The store in the shared App Group suite.
    static var shared: SharedPrayerConfigStore {
        SharedPrayerConfigStore(defaults: UserDefaults(suiteName: appGroupIdentifier))
    }

    /// The stored config, or nil when there is none or it cannot be read.
    func load() -> SharedPrayerConfig? {
        guard let data = defaults?.data(forKey: Self.storageKey),
              let config = try? JSONDecoder().decode(SharedPrayerConfig.self, from: data),
              config.isValid
        else {
            return nil
        }
        return config
    }

    /// The stored config, or the Makkah fallback.
    func loadOrFallback() -> SharedPrayerConfig {
        load() ?? .fallback
    }

    /// Stores `config`. Returns true only when the stored value changed, so callers
    /// reload widget timelines only when there is something new to show.
    @discardableResult
    func save(_ config: SharedPrayerConfig) -> Bool {
        guard let defaults = defaults, config != load(),
              let data = try? JSONEncoder().encode(config)
        else {
            return false
        }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}
