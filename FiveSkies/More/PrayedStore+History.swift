import Foundation

extension PrayedStore {
    /// Day keys ("yyyy-MM-dd") on which all five prayers are marked as prayed.
    /// Reads the same UserDefaults entry PrayedStore writes, a JSON dictionary of day key to prayers.
    static func completeDayKeys(in defaults: UserDefaults = .standard) -> Set<String> {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Set<Prayer>].self, from: data)
        else {
            return []
        }
        let everyPrayer = Set(Prayer.allCases)
        return Set(decoded.compactMap { key, prayers in
            prayers.isSuperset(of: everyPrayer) ? key : nil
        })
    }
}
