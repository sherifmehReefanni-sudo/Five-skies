import Foundation

/// How a prayer announces itself on the lock screen.
enum AlertMode: String, Codable, CaseIterable, Identifiable {
    case off
    case silent
    case sound

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .silent: return "Silent"
        case .sound: return "Sound"
        }
    }
}

/// The prayer time calculation methods offered in settings.
/// Case names match the Adhan library's `CalculationMethod` cases one to one.
enum PrayerCalculationMethod: String, Codable, CaseIterable, Identifiable {
    case muslimWorldLeague
    case egyptian
    case karachi
    case ummAlQura
    case dubai
    case moonsightingCommittee
    case northAmerica
    case kuwait
    case qatar
    case singapore
    case tehran
    case turkey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muslimWorldLeague: return "Muslim World League"
        case .egyptian: return "Egyptian General Authority of Survey"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .ummAlQura: return "Umm al-Qura University, Makkah"
        case .dubai: return "Dubai (UAE)"
        case .moonsightingCommittee: return "Moonsighting Committee"
        case .northAmerica: return "ISNA (North America)"
        case .kuwait: return "Kuwait"
        case .qatar: return "Qatar"
        case .singapore: return "Singapore, Malaysia, Indonesia"
        case .tehran: return "Institute of Geophysics, Tehran"
        case .turkey: return "Diyanet (Turkey)"
        }
    }
}

/// Which shadow length starts Asr.
enum AsrRule: String, Codable, CaseIterable, Identifiable {
    case standard
    case hanafi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard (Shafi'i, Maliki, Hanbali)"
        case .hanafi: return "Hanafi"
        }
    }
}

/// When the Isha window is shown as ending. Schools differ; see DayDefinitions.swift.
enum IshaEndRule: String, Codable, CaseIterable, Identifiable {
    case middleOfNight
    case fajr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .middleOfNight: return "Middle of the night"
        case .fajr: return "Fajr"
        }
    }
}

/// The alert part of the settings as a plain value, used to build the notification plan.
struct AlertPreferences: Equatable {
    var modes: [Prayer: AlertMode]
    var reminderMinutesBefore: Int

    func mode(for prayer: Prayer) -> AlertMode {
        modes[prayer] ?? AppSettings.defaultAlertMode
    }

    /// Whether any prayer would produce a notification.
    var wantsAnyAlert: Bool {
        Prayer.allCases.contains { mode(for: $0) != .off }
    }
}

/// Everything in settings as one Equatable value, so views can react to any change.
struct SettingsSnapshot: Equatable {
    let calculationMethod: PrayerCalculationMethod
    let asrRule: AsrRule
    let ishaEnd: IshaEndRule
    let alerts: AlertPreferences
}

/// The user's settings, persisted in UserDefaults one key per value.
final class AppSettings: ObservableObject {
    static let defaultCalculationMethod = PrayerCalculationMethod.northAmerica
    static let defaultAsrRule = AsrRule.standard
    static let defaultAlertMode = AlertMode.sound
    static let defaultReminderMinutes = 0
    /// Minutes before a prayer for the optional reminder. 0 means no reminder.
    static let reminderOptions = [0, 5, 10, 15, 30]
    static let defaultIshaEnd = IshaEndRule.middleOfNight
    /// Days added to the calculated Hijri date, to match local moon sighting.
    static let hijriAdjustmentRange = -2...2

    enum Keys {
        static let calculationMethod = "settings.calculationMethod"
        static let asrRule = "settings.asrRule"
        static let reminderMinutesBefore = "settings.reminderMinutesBefore"
        static let ishaEnd = "settings.ishaEnd"
        static let hijriAdjustment = "settings.hijriAdjustment"
        static func alertMode(for prayer: Prayer) -> String {
            "settings.alertMode.\(prayer.rawValue)"
        }
    }

    @Published var calculationMethod: PrayerCalculationMethod {
        didSet { defaults.set(calculationMethod.rawValue, forKey: Keys.calculationMethod) }
    }

    @Published var asrRule: AsrRule {
        didSet { defaults.set(asrRule.rawValue, forKey: Keys.asrRule) }
    }

    /// One mode per prayer. Read and write through `alertMode(for:)` and `setAlertMode(_:for:)`.
    @Published private(set) var alertModes: [Prayer: AlertMode]

    @Published var reminderMinutesBefore: Int {
        didSet { defaults.set(reminderMinutesBefore, forKey: Keys.reminderMinutesBefore) }
    }

    @Published var ishaEnd: IshaEndRule {
        didSet { defaults.set(ishaEnd.rawValue, forKey: Keys.ishaEnd) }
    }

    /// -2 to +2 days, added to the Umm al-Qura date wherever a Hijri date is shown.
    @Published var hijriAdjustment: Int {
        didSet {
            let clamped = min(max(hijriAdjustment, Self.hijriAdjustmentRange.lowerBound), Self.hijriAdjustmentRange.upperBound)
            if clamped != hijriAdjustment {
                hijriAdjustment = clamped
                return
            }
            defaults.set(hijriAdjustment, forKey: Keys.hijriAdjustment)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let method = defaults.string(forKey: Keys.calculationMethod)
            .flatMap(PrayerCalculationMethod.init(rawValue:)) ?? Self.defaultCalculationMethod
        let rule = defaults.string(forKey: Keys.asrRule)
            .flatMap(AsrRule.init(rawValue:)) ?? Self.defaultAsrRule

        var modes: [Prayer: AlertMode] = [:]
        for prayer in Prayer.allCases {
            modes[prayer] = defaults.string(forKey: Keys.alertMode(for: prayer))
                .flatMap(AlertMode.init(rawValue:)) ?? Self.defaultAlertMode
        }

        var minutes = Self.defaultReminderMinutes
        if let stored = defaults.object(forKey: Keys.reminderMinutesBefore) as? Int,
           Self.reminderOptions.contains(stored) {
            minutes = stored
        }

        _calculationMethod = Published(initialValue: method)
        _asrRule = Published(initialValue: rule)
        _alertModes = Published(initialValue: modes)
        _reminderMinutesBefore = Published(initialValue: minutes)

        let ishaEnd = defaults.string(forKey: Keys.ishaEnd)
            .flatMap(IshaEndRule.init(rawValue:)) ?? Self.defaultIshaEnd
        var adjustment = 0
        if let stored = defaults.object(forKey: Keys.hijriAdjustment) as? Int,
           Self.hijriAdjustmentRange.contains(stored) {
            adjustment = stored
        }
        _ishaEnd = Published(initialValue: ishaEnd)
        _hijriAdjustment = Published(initialValue: adjustment)
    }

    func alertMode(for prayer: Prayer) -> AlertMode {
        alertModes[prayer] ?? Self.defaultAlertMode
    }

    func setAlertMode(_ mode: AlertMode, for prayer: Prayer) {
        alertModes[prayer] = mode
        defaults.set(mode.rawValue, forKey: Keys.alertMode(for: prayer))
    }

    var alertPreferences: AlertPreferences {
        AlertPreferences(modes: alertModes, reminderMinutesBefore: reminderMinutesBefore)
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(calculationMethod: calculationMethod, asrRule: asrRule, ishaEnd: ishaEnd, alerts: alertPreferences)
    }
}
