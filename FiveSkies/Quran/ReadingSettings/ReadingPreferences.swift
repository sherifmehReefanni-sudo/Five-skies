import Foundation

/// The background behind the Quran screens, picked in the Reading sheet.
enum QuranBackground: String, CaseIterable, Identifiable {
    case sky
    case plainDark

    var id: String { rawValue }

    /// The short name shown under its swatch.
    var title: String {
        switch self {
        case .sky:
            return "Sky"
        case .plainDark:
            return "Plain dark"
        }
    }
}

/// The reader's saved choices from the Reading sheet ("Aa"), read and written in UserDefaults.
/// The views use `@AppStorage` with the same keys and defaults, so both always agree.
struct ReadingPreferences {
    /// The same key, range and default as `SurahReaderView.textSizeKey`, `textSizeRange` and
    /// `defaultTextSize`, so nobody loses their saved size. A unit test keeps them equal.
    static let textSizeKey = "quranArabicTextSize"
    static let textSizeRange: ClosedRange<Double> = 22...44
    static let defaultTextSize: Double = 30

    /// Whether the chosen translation shows under each ayah. On by default (E1.5), so a
    /// downloaded translation appears without the person finding a switch.
    static let showsTranslationKey = "reading.showsTranslation"
    static let defaultShowsTranslation = true

    static let backgroundKey = "reading.background"
    static let defaultBackground: QuranBackground = .sky

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved switch for the standard defaults, for code that cannot use `@AppStorage`.
    static var showsTranslation: Bool {
        ReadingPreferences().showsTranslation
    }

    var showsTranslation: Bool {
        get { defaults.object(forKey: Self.showsTranslationKey) as? Bool ?? Self.defaultShowsTranslation }
        nonmutating set { defaults.set(newValue, forKey: Self.showsTranslationKey) }
    }

    /// The saved background. An unknown saved value falls back to the sky.
    var background: QuranBackground {
        get {
            defaults.string(forKey: Self.backgroundKey).flatMap(QuranBackground.init(rawValue:)) ?? Self.defaultBackground
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.backgroundKey) }
    }

    /// The Arabic size in points, always inside `textSizeRange`.
    var textSize: Double {
        get {
            let saved = defaults.object(forKey: Self.textSizeKey) as? Double ?? Self.defaultTextSize
            return Self.clamped(saved)
        }
        nonmutating set { defaults.set(Self.clamped(newValue), forKey: Self.textSizeKey) }
    }

    static func clamped(_ size: Double) -> Double {
        min(max(size, textSizeRange.lowerBound), textSizeRange.upperBound)
    }
}
