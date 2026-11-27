import Foundation

/// Decides whether the first-run flow shows at launch, and what it may do while it shows.
/// Pure apart from the `live()` and `markCompleted(in:)` helpers, so the rules are unit tested.
///
/// - Shows once, until the flow is finished or skipped ("onboarding.completed" in UserDefaults).
/// - Never shows in the fixed phase UI test mode or in the unit test host,
///   unless `-FSShowOnboarding` is passed (for screenshots).
/// - With `-FSShowOnboarding` it never asks for a permission and records nothing:
///   the buttons only move to the next page.
struct OnboardingGate: Equatable {
    static let completedKey = "onboarding.completed"
    static let showArgument = "-FSShowOnboarding"

    let isCompleted: Bool
    let isFixedPhase: Bool
    let isUnitTestHost: Bool
    /// `-FSShowOnboarding` is among the launch arguments.
    let isForced: Bool

    init(isCompleted: Bool, isFixedPhase: Bool, isUnitTestHost: Bool, isForced: Bool) {
        self.isCompleted = isCompleted
        self.isFixedPhase = isFixedPhase
        self.isUnitTestHost = isUnitTestHost
        self.isForced = isForced
    }

    init(defaults: UserDefaults, launch: LaunchOptions, arguments: [String]) {
        self.init(
            isCompleted: defaults.bool(forKey: Self.completedKey),
            isFixedPhase: launch.fixedPhase != nil,
            isUnitTestHost: launch.isUnitTestHost,
            isForced: arguments.contains(Self.showArgument)
        )
    }

    /// The gate for this launch of the app.
    static func live() -> OnboardingGate {
        OnboardingGate(
            defaults: .standard,
            launch: LaunchOptions(),
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    /// Whether the flow is presented at launch.
    var shouldShow: Bool {
        if isForced {
            return true
        }
        if isFixedPhase || isUnitTestHost {
            return false
        }
        return !isCompleted
    }

    /// Whether the buttons may ask for location and notification permission.
    var requestsPermissions: Bool {
        !isForced && !isFixedPhase && !isUnitTestHost
    }

    /// Whether finishing or skipping writes the completed flag. Screenshot runs leave no trace.
    var recordsCompletion: Bool {
        !isForced
    }

    static func markCompleted(in defaults: UserDefaults) {
        defaults.set(true, forKey: completedKey)
    }
}

/// The pages of the first-run flow, in order. Four at most.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case location
    case alerts
    case done

    var id: Int { rawValue }

    /// 1 to 4, for the page dots and the accessibility identifiers.
    var number: Int { rawValue + 1 }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }

    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    var isLast: Bool { next == nil }

    /// Each page has its own sky.
    var sky: Prayer {
        switch self {
        case .welcome: return .fajr
        case .location: return .dhuhr
        case .alerts: return .maghrib
        case .done: return .isha
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .location: return "location.fill"
        case .alerts: return "bell.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Welcome to Five Skies"
        case .location: return "Times for where you are"
        case .alerts: return "A gentle call to prayer"
        case .done: return "You are all set"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Prayer times, the Qibla and the Quran, under a sky that follows your day. Free, with no ads and no account."
        case .location:
            return Self.locationReason
        case .alerts:
            return "Each prayer has its own alert: sound, silent or off. All five start with sound, and you can change each one any time from the gear on Today."
        case .done:
            return "Tap a prayer on Today when you have prayed it, and watch the sky change through the day."
        }
    }

    /// Matches NSLocationWhenInUseUsageDescription in project.yml.
    static let locationReason = "Prayer times and the Qibla are calculated on your iPhone. Your location is never sent anywhere."

    var primaryTitle: String {
        switch self {
        case .welcome: return "Get started"
        case .location: return "Allow location"
        case .alerts: return "Allow alerts"
        case .done: return "Open Today"
        }
    }

    /// The quiet second choice under the gold button, on the pages that ask for something.
    var secondaryTitle: String? {
        switch self {
        case .location, .alerts: return "Not now"
        case .welcome, .done: return nil
        }
    }

    var titleIdentifier: String { "onboardingTitle-\(number)" }

    var primaryIdentifier: String { isLast ? "onboardingDone" : "onboardingNext" }
}
