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

/// What the night alarm is set relative to.
enum NightAlarmAnchor: String, Codable, CaseIterable, Identifiable {
    case lastThirdOfNight
    case fajr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lastThirdOfNight: return "Last third of the night"
        case .fajr: return "Fajr"
        }
    }
}

/// The night alarm settings as a plain value.
/// `weekdays` uses Calendar weekday numbers (1 is Sunday, 7 is Saturday) and names
/// the days on which the alarm rings, like the Clock app.
struct NightAlarmSettings: Equatable {
    var isEnabled: Bool = false
    var anchor: NightAlarmAnchor = .lastThirdOfNight
    var offsetMinutes: Int = 0
    var weekdays: Set<Int> = NightAlarmSettings.everyDay

    static let everyDay: Set<Int> = Set(1...7)
    /// -60 to +60 minutes in steps of 5.
    static let offsetOptions: [Int] = Array(stride(from: -60, through: 60, by: 5))

    /// "15 minutes before", "At the time", "10 minutes after".
    static func offsetLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "At the time" }
        let size = abs(minutes)
        let unit = size == 1 ? "minute" : "minutes"
        return minutes < 0 ? "\(size) \(unit) before" : "\(size) \(unit) after"
    }
}

/// The alert part of the settings as a plain value, used to build the notification plan.
struct AlertPreferences: Equatable {
    var modes: [Prayer: AlertMode]
    var reminderMinutesBefore: Int
    /// Minutes before a prayer's window ends for the "ends soon" reminder. 0 means off.
    var endReminderMinutes: Int = 0
    /// Where the Isha window ends, for the "ends soon" reminder.
    var ishaEnd: IshaEndRule = AppSettings.defaultIshaEnd
    var nightAlarm: NightAlarmSettings = NightAlarmSettings()

    func mode(for prayer: Prayer) -> AlertMode {
        modes[prayer] ?? AppSettings.defaultAlertMode
    }

    /// Whether any prayer would produce a notification.
    var wantsAnyAlert: Bool {
        Prayer.allCases.contains { mode(for: $0) != .off }
    }

    /// Whether anything in these preferences needs notification permission.
    /// The night alarm counts because notifications are its fallback before iOS 26.
    var needsNotificationPermission: Bool {
        wantsAnyAlert || nightAlarm.isEnabled
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
    /// Minutes before a prayer's window ends for the optional reminder. 0 means off.
    static let endReminderOptions = [0, 10, 15, 20, 30]

    enum Keys {
        static let calculationMethod = "settings.calculationMethod"
        static let asrRule = "settings.asrRule"
        static let reminderMinutesBefore = "settings.reminderMinutesBefore"
        static let ishaEnd = "settings.ishaEnd"
        static let hijriAdjustment = "settings.hijriAdjustment"
        static let endReminderMinutes = "settings.endReminderMinutes"
        static let nightAlarmEnabled = "settings.nightAlarm.enabled"
        static let nightAlarmAnchor = "settings.nightAlarm.anchor"
        static let nightAlarmOffset = "settings.nightAlarm.offsetMinutes"
        static let nightAlarmWeekdays = "settings.nightAlarm.weekdays"
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

    @Published var endReminderMinutes: Int {
        didSet { defaults.set(endReminderMinutes, forKey: Keys.endReminderMinutes) }
    }

    /// Off by default.
    @Published var nightAlarmEnabled: Bool {
        didSet { defaults.set(nightAlarmEnabled, forKey: Keys.nightAlarmEnabled) }
    }

    @Published var nightAlarmAnchor: NightAlarmAnchor {
        didSet { defaults.set(nightAlarmAnchor.rawValue, forKey: Keys.nightAlarmAnchor) }
    }

    /// Minutes from the anchor, negative for before. One of `NightAlarmSettings.offsetOptions`.
    @Published var nightAlarmOffsetMinutes: Int {
        didSet { defaults.set(nightAlarmOffsetMinutes, forKey: Keys.nightAlarmOffset) }
    }

    /// Calendar weekday numbers (1 is Sunday) on which the night alarm rings.
    @Published var nightAlarmWeekdays: Set<Int> {
        didSet { defaults.set(nightAlarmWeekdays.sorted(), forKey: Keys.nightAlarmWeekdays) }
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

        var endMinutes = 0
        if let stored = defaults.object(forKey: Keys.endReminderMinutes) as? Int,
           Self.endReminderOptions.contains(stored) {
            endMinutes = stored
        }
        let night = NightAlarmSettings()
        let nightEnabled = defaults.object(forKey: Keys.nightAlarmEnabled) as? Bool ?? night.isEnabled
        let anchor = defaults.string(forKey: Keys.nightAlarmAnchor)
            .flatMap(NightAlarmAnchor.init(rawValue:)) ?? night.anchor
        var offset = night.offsetMinutes
        if let stored = defaults.object(forKey: Keys.nightAlarmOffset) as? Int,
           NightAlarmSettings.offsetOptions.contains(stored) {
            offset = stored
        }
        var weekdays = night.weekdays
        if let stored = defaults.array(forKey: Keys.nightAlarmWeekdays) as? [Int] {
            let valid = Set(stored.filter { NightAlarmSettings.everyDay.contains($0) })
            if !valid.isEmpty {
                weekdays = valid
            }
        }
        _endReminderMinutes = Published(initialValue: endMinutes)
        _nightAlarmEnabled = Published(initialValue: nightEnabled)
        _nightAlarmAnchor = Published(initialValue: anchor)
        _nightAlarmOffsetMinutes = Published(initialValue: offset)
        _nightAlarmWeekdays = Published(initialValue: weekdays)
    }

    func alertMode(for prayer: Prayer) -> AlertMode {
        alertModes[prayer] ?? Self.defaultAlertMode
    }

    func setAlertMode(_ mode: AlertMode, for prayer: Prayer) {
        alertModes[prayer] = mode
        defaults.set(mode.rawValue, forKey: Keys.alertMode(for: prayer))
    }

    var nightAlarm: NightAlarmSettings {
        NightAlarmSettings(
            isEnabled: nightAlarmEnabled,
            anchor: nightAlarmAnchor,
            offsetMinutes: nightAlarmOffsetMinutes,
            weekdays: nightAlarmWeekdays
        )
    }

    var alertPreferences: AlertPreferences {
        AlertPreferences(
            modes: alertModes,
            reminderMinutesBefore: reminderMinutesBefore,
            endReminderMinutes: endReminderMinutes,
            ishaEnd: ishaEnd,
            nightAlarm: nightAlarm
        )
    }

    var snapshot: SettingsSnapshot {
        SettingsSnapshot(calculationMethod: calculationMethod, asrRule: asrRule, ishaEnd: ishaEnd, alerts: alertPreferences)
    }
}
