import Foundation

/// Clock style times for the player.
enum ListenTimeFormat {
    /// "3:05", or "1:02:03" from an hour up. Negative and non finite values show as 0:00.
    static func clock(_ seconds: Double) -> String {
        let (hours, minutes, secs) = parts(seconds)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Time left, as "-3:05".
    static func remaining(position: Double, duration: Double) -> String {
        "-" + clock(max(0, safe(duration) - safe(position)))
    }

    /// For VoiceOver: "1 hour 2 minutes 3 seconds", "0 seconds".
    static func spoken(_ seconds: Double) -> String {
        let (hours, minutes, secs) = parts(seconds)
        var words: [String] = []
        if hours > 0 {
            words.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if minutes > 0 {
            words.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if secs > 0 || words.isEmpty {
            words.append(secs == 1 ? "1 second" : "\(secs) seconds")
        }
        return words.joined(separator: " ")
    }

    private static func safe(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func parts(_ seconds: Double) -> (Int, Int, Int) {
        let total = Int(max(0, safe(seconds)).rounded(.down))
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}

/// The playback speeds offered in the player.
enum ListenSpeed {
    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// "0.75x", "1x", "1.5x".
    static func label(_ rate: Float) -> String {
        number(rate) + "x"
    }

    /// For VoiceOver: "Normal speed", "1.5 times speed".
    static func spoken(_ rate: Float) -> String {
        matches(rate, 1) ? "Normal speed" : "\(number(rate)) times speed"
    }

    static func matches(_ lhs: Float, _ rhs: Float) -> Bool {
        abs(lhs - rhs) < 0.01
    }

    private static func number(_ rate: Float) -> String {
        var text = String(format: "%.2f", Double(rate))
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}

/// The sleep timer choices.
enum ListenSleepOption: Hashable, Identifiable {
    case off
    case minutes(Int)
    case endOfSurah

    static let all: [ListenSleepOption] = [
        .off, .minutes(5), .minutes(10), .minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfSurah
    ]

    var id: String { identifier }

    var title: String {
        switch self {
        case .off: return "Off"
        case .minutes(let minutes): return "\(minutes) minutes"
        case .endOfSurah: return "End of surah"
        }
    }

    var identifier: String {
        switch self {
        case .off: return "sleepOff"
        case .minutes(let minutes): return "sleep-\(minutes)"
        case .endOfSurah: return "sleepEndOfSurah"
        }
    }

    /// What the sleep timer is set to now, from the last choice and what the player reports.
    /// A minutes timer counts only while the player still has an end date; "End of surah"
    /// counts only for the surah it was chosen on.
    static func current(
        chosen: ListenSleepOption,
        chosenChapter: Int?,
        playingChapter: Int?,
        timerEnd: Date?
    ) -> ListenSleepOption {
        switch chosen {
        case .off:
            return .off
        case .minutes:
            return timerEnd == nil ? .off : chosen
        case .endOfSurah:
            return chosenChapter != nil && chosenChapter == playingChapter ? .endOfSurah : .off
        }
    }
}

/// The last sleep timer choice, kept by the Quran tab while the player sheet comes and goes.
struct ListenSleepChoice: Equatable {
    var option: ListenSleepOption = .off
    var chapter: Int?
}

/// Words for the play modes (docs/LEARN_LISTEN_PLAN.md section 3).
enum ListenPlayModeText {
    static let timingsNote = "Needs word timings for this reciter"
    static let yourTurn = "Your turn"

    static func surahEnd(_ action: SurahEndAction) -> String {
        switch action {
        case .stop:
            return "Stop"
        case .playNext:
            return "Play the next surah"
        case .repeatSurah(let times):
            return repeatSurah(times)
        case .playSet(let first, let last):
            return "Surahs \(first) to \(last)"
        }
    }

    static func repeatSurah(_ times: Int?) -> String {
        guard let times else { return "Repeat until stopped" }
        return times == 1 ? "Repeat 1 time" : "Repeat \(times) times"
    }

    /// 1 means each ayah plays once, so the repeat is off.
    static func ayahRepeat(_ count: Int) -> String {
        count <= 1 ? "Off" : "\(count) times"
    }

    static func prayerPause(_ prayer: String) -> String {
        "Paused for \(prayer). Resume?"
    }
}

/// Keeps a "surahs from A to B" choice in order and inside 1 to 114.
enum ListenSetRange {
    static let chapters = 1...114

    static func clamp(_ chapter: Int) -> Int {
        min(max(chapter, chapters.lowerBound), chapters.upperBound)
    }

    /// The first choice of a set: from the surah playing now to the last surah.
    static func starting(at chapter: Int) -> SurahEndAction {
        .playSet(first: clamp(chapter), last: chapters.upperBound)
    }

    /// A new first surah; the last moves up with it when needed.
    static func changingFirst(_ first: Int, last: Int) -> SurahEndAction {
        let newFirst = clamp(first)
        return .playSet(first: newFirst, last: max(newFirst, clamp(last)))
    }

    /// A new last surah; the first moves down with it when needed.
    static func changingLast(_ last: Int, first: Int) -> SurahEndAction {
        let newLast = clamp(last)
        return .playSet(first: min(clamp(first), newLast), last: newLast)
    }
}

/// The credit line for a reciter before anything plays, in the same form as `NowPlayingItem.credit` (D9).
enum ListenCreditLine {
    static func text(for reciter: Reciter) -> String {
        "\(reciter.name) \u{00B7} Quran Foundation"
    }
}
