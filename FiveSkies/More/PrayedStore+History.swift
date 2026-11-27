import Foundation

extension PrayedStore {
    /// Day keys ("yyyy-MM-dd") on which all five prayers are marked as prayed.
    /// Reads the same UserDefaults entry PrayedStore writes, a JSON dictionary of day key to prayers.
    static func completeDayKeys(in defaults: UserDefaults = .standard) -> Set<String> {
        let everyPrayer = Set(Prayer.allCases)
        return Set(storedDays(in: defaults).compactMap { key, prayers in
            prayers.isSuperset(of: everyPrayer) ? key : nil
        })
    }

    /// The earliest day key with at least one prayer marked, or nil before the user ever tracked.
    /// Counting in the tracker starts on this day; nothing before it is shown as unmarked.
    static func firstTrackedDayKey(in defaults: UserDefaults = .standard) -> String? {
        storedDays(in: defaults).compactMap { key, prayers in
            prayers.isEmpty ? nil : key
        }.min()
    }

    private static func storedDays(in defaults: UserDefaults) -> [String: Set<Prayer>] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Set<Prayer>].self, from: data)
        else {
            return [:]
        }
        return decoded
    }
}
