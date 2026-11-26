import Adhan
import Foundation

// Kept apart from AppSettings.swift so files that use the app's own `Prayer`
// type never import Adhan, which has a `Prayer` type of its own.

extension PrayerCalculationMethod {
    /// The matching Adhan calculation method.
    var adhanMethod: CalculationMethod {
        switch self {
        case .muslimWorldLeague: return .muslimWorldLeague
        case .egyptian: return .egyptian
        case .karachi: return .karachi
        case .ummAlQura: return .ummAlQura
        case .dubai: return .dubai
        case .moonsightingCommittee: return .moonsightingCommittee
        case .northAmerica: return .northAmerica
        case .kuwait: return .kuwait
        case .qatar: return .qatar
        case .singapore: return .singapore
        case .tehran: return .tehran
        case .turkey: return .turkey
        }
    }

    /// The raw value of the matching Adhan method, so tests can check the mapping without importing Adhan.
    var adhanMethodName: String {
        adhanMethod.rawValue
    }
}

extension AsrRule {
    /// The matching Adhan madhab.
    var madhab: Madhab {
        switch self {
        case .standard: return .shafi
        case .hanafi: return .hanafi
        }
    }

    /// The Adhan madhab raw value: the shadow length factor, 1 for standard and 2 for Hanafi.
    var shadowFactor: Int {
        madhab.rawValue
    }
}
