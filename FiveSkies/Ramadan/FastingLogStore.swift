import Foundation

/// Remembers fasted Ramadan days, voluntary fasts and Taraweeh nights in UserDefaults.
/// Ramadan days are keyed by Hijri year and day; the others by Hijri date key.
struct FastingLogStore {
    static let ramadanKey = "ramadan.fastedDays"
    static let voluntaryKey = "ramadan.voluntaryFasts"
    static let taraweehKey = "ramadan.taraweehNights"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Ramadan days

    func fastedDays(inRamadanOf year: Int) -> Set<Int> {
        Set(loadRamadan()[String(year)] ?? [])
    }

    func isFasted(day: Int, year: Int) -> Bool {
        fastedDays(inRamadanOf: year).contains(day)
    }

    func setFasted(_ fasted: Bool, day: Int, year: Int) {
        guard (1...RamadanCalendar.logDayCount).contains(day) else { return }
        var all = loadRamadan()
        var days = Set(all[String(year)] ?? [])
        if fasted {
            days.insert(day)
        } else {
            days.remove(day)
        }
        all[String(year)] = days.isEmpty ? nil : days.sorted()
        saveRamadan(all)
    }

    // MARK: - Voluntary fasts

    var voluntaryFastCount: Int {
        loadKeys(Self.voluntaryKey).count
    }

    func isVoluntaryFastLogged(on day: HijriDay) -> Bool {
        loadKeys(Self.voluntaryKey).contains(day.key)
    }

    func setVoluntaryFast(_ logged: Bool, on day: HijriDay) {
        setKey(day.key, included: logged, in: Self.voluntaryKey)
    }

    // MARK: - Any fast

    /// Whether any fast is logged on this Hijri day: a Ramadan day or a voluntary fast.
    func hasFastLogged(on day: HijriDay) -> Bool {
        if day.month == RamadanCalendar.ramadanMonth, isFasted(day: day.day, year: day.year) {
            return true
        }
        return isVoluntaryFastLogged(on: day)
    }

    // MARK: - Taraweeh

    func prayedTaraweeh(on day: HijriDay) -> Bool {
        loadKeys(Self.taraweehKey).contains(day.key)
    }

    func setTaraweeh(_ prayed: Bool, on day: HijriDay) {
        setKey(day.key, included: prayed, in: Self.taraweehKey)
    }

    // MARK: - Storage

    private func loadRamadan() -> [String: [Int]] {
        guard let data = defaults.data(forKey: Self.ramadanKey),
              let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func saveRamadan(_ all: [String: [Int]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: Self.ramadanKey)
    }

    private func loadKeys(_ storageKey: String) -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    private func setKey(_ key: String, included: Bool, in storageKey: String) {
        var keys = loadKeys(storageKey)
        if included {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        defaults.set(keys.sorted(), forKey: storageKey)
    }
}
