import Foundation

/// How many rakahs (units of prayer) each obligatory prayer has (plan N4). On the scholar sheet.
/// Only the obligatory count: sunnah prayers are left out because schools count them differently.
/// Friday is not treated differently here.
enum RakahCount {
    /// Fajr 2, Dhuhr 4, Asr 4, Maghrib 3, Isha 4.
    static func obligatory(for prayer: Prayer) -> Int? {
        switch prayer {
        case .fajr: return 2
        case .dhuhr: return 4
        case .asr: return 4
        case .maghrib: return 3
        case .isha: return 4
        }
    }

    /// The small caption under a prayer row, as in "2 rakahs". nil when there is no count.
    static func caption(for count: Int?) -> String? {
        guard let count = count, count > 0 else { return nil }
        return count == 1 ? "1 rakah" : "\(count) rakahs"
    }
}
