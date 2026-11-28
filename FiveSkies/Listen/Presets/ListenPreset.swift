import Foundation

/// One-tap starting points at the top of the player sheet's play modes (docs/READER_EASE_PLAN.md
/// E2.1). Each preset only sets the existing `PlayModes`; "Custom" is any other mix, made with the
/// detailed controls below. Presets never touch when the surah ends or pausing for prayer.
enum ListenPreset: CaseIterable, Equatable {
    case listen
    case understand
    case memorize

    var title: String {
        switch self {
        case .listen: return "Listen"
        case .understand: return "Understand"
        case .memorize: return "Memorize"
        }
    }

    /// One line shown under the row for the selected preset.
    var subtitle: String {
        switch self {
        case .listen: return "Plays through, text follows"
        case .understand: return "Meaning shown and read after each ayah"
        case .memorize: return "Each ayah 3 times, then your turn"
        }
    }

    var symbol: String {
        switch self {
        case .listen: return "headphones"
        case .understand: return "text.bubble.fill"
        case .memorize: return "brain.head.profile"
        }
    }

    var identifier: String {
        switch self {
        case .listen: return "presetListen"
        case .understand: return "presetUnderstand"
        case .memorize: return "presetMemorize"
        }
    }

    /// Understand and Memorize follow single ayahs, so they need timings for the reciter.
    var needsTimings: Bool {
        switch self {
        case .listen: return false
        case .understand, .memorize: return true
        }
    }

    /// Understand reads the chosen translation, so it needs one.
    var needsTranslation: Bool {
        self == .understand
    }

    /// Understand also turns on the reader's meaning and transliteration (wired by the lead).
    var showsReadingAids: Bool {
        self == .understand
    }

    /// The modes with this preset's four fields set. `surahEnd` and `pausesForPrayer` are kept.
    func applied(to modes: PlayModes) -> PlayModes {
        var result = modes
        switch self {
        case .listen:
            result.ayahRepeat = 1
            result.reciteAfterMe = false
            result.readsMeaning = false
            result.hidesAyahWhileWaiting = false
        case .understand:
            result.ayahRepeat = 1
            result.reciteAfterMe = false
            result.readsMeaning = true
            result.hidesAyahWhileWaiting = false
        case .memorize:
            result.ayahRepeat = 3
            result.reciteAfterMe = true
            result.readsMeaning = false
            result.hidesAyahWhileWaiting = true
        }
        return result
    }

    /// The preset these modes match, comparing only the four fields a preset sets. Nil means Custom.
    static func matching(_ modes: PlayModes) -> ListenPreset? {
        allCases.first { preset in
            let target = preset.applied(to: modes)
            return target.ayahRepeat == modes.ayahRepeat
                && target.reciteAfterMe == modes.reciteAfterMe
                && target.readsMeaning == modes.readsMeaning
                && target.hidesAyahWhileWaiting == modes.hidesAyahWhileWaiting
        }
    }
}
