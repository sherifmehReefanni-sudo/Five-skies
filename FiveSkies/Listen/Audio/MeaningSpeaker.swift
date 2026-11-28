import AVFoundation
import Foundation

/// Reads an ayah's English meaning aloud between ayahs (docs/LEARN_LISTEN_PLAN.md section 6:
/// an English computer voice for English text only, never for any Arabic, Quran or dua).
/// `LiveMeaningSpeaker` uses AVSpeechSynthesizer; `SimulatedMeaningSpeaker` is silent and is used
/// in unit tests and under `-FSFakeListen`, so tests and screenshots never speak.
@MainActor
protocol MeaningSpeaking: AnyObject {
    /// Starts reading `text`. Calls `completion` once when the reading ends by itself.
    /// After `stop()` the completion of the stopped reading is never called.
    func speak(_ text: String, completion: @escaping @MainActor () -> Void)
    /// Stops at once. Safe to call when nothing is being read.
    func stop()
}

/// Checks for the meaning reader. Pure functions, no Arabic literals (scalar ranges only).
enum ListenMeaningText {
    /// The line the player shows while a meaning is read, for example "Meaning · Translator".
    static func label(for meaning: AyahMeaning) -> String {
        "Meaning \u{00B7} \(meaning.source)"
    }

    /// Unicode blocks of the Arabic script, as code point ranges.
    static let arabicScriptRanges: [ClosedRange<UInt32>] = [
        0x0600...0x06FF, // Arabic
        0x0750...0x077F, // Arabic Supplement
        0x0870...0x089F, // Arabic Extended-B
        0x08A0...0x08FF, // Arabic Extended-A
        0xFB50...0xFDFF, // Arabic Presentation Forms-A
        0xFE70...0xFEFF, // Arabic Presentation Forms-B
        0x10E60...0x10E7F, // Rumi Numeral Symbols
        0x10EC0...0x10EFF, // Arabic Extended-C
        0x1EC70...0x1ECBF, // Indic Siyaq Numbers
        0x1ED00...0x1ED4F, // Ottoman Siyaq Numbers
        0x1EE00...0x1EEFF, // Arabic Mathematical Alphabetic Symbols
    ]

    static func containsArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            arabicScriptRanges.contains { $0.contains(scalar.value) }
        }
    }

    /// True only for text a computer voice may read: some letters or digits, and not one
    /// scalar from an Arabic block.
    static func isSpeakable(_ text: String) -> Bool {
        guard !containsArabicScript(text) else { return false }
        return text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    /// Language codes to try for the voice, best first: the listener's own English choices
    /// (for example "en-GB"), then "en-US". Codes that are not English are left out.
    static func voiceLanguages(preferred: [String]) -> [String] {
        var codes: [String] = []
        for code in preferred where isEnglish(code) && !codes.contains(code) {
            codes.append(code)
        }
        if !codes.contains("en-US") {
            codes.append("en-US")
        }
        return codes
    }

    static func isEnglish(_ languageCode: String) -> Bool {
        let lower = languageCode.lowercased()
        return lower == "en" || lower.hasPrefix("en-") || lower.hasPrefix("en_")
    }
}

/// Reads with AVSpeechSynthesizer in an English voice, at a calm pace.
/// It uses the app's audio session (`.playback`, `.spokenAudio`, set by `LiveListenSystem`),
/// so it keeps reading with the screen locked, like the recitation.
@MainActor
final class LiveMeaningSpeaker: NSObject, MeaningSpeaking, AVSpeechSynthesizerDelegate {
    /// A little slower than the system default.
    static let calmRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9
    static let pauseAround: TimeInterval = 0.3

    private let synthesizer = AVSpeechSynthesizer()
    private var currentID: ObjectIdentifier?
    /// Kept so the identifier above stays unique while it is read.
    private var current: AVSpeechUtterance?
    private var completion: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.usesApplicationAudioSession = true
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping @MainActor () -> Void) {
        stop()
        // A second guard behind the player's: never a computer voice for Arabic.
        guard ListenMeaningText.isSpeakable(text), let voice = Self.englishVoice() else {
            Task { @MainActor in completion() }
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.calmRate
        utterance.preUtteranceDelay = Self.pauseAround
        utterance.postUtteranceDelay = Self.pauseAround
        current = utterance
        currentID = ObjectIdentifier(utterance)
        self.completion = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        currentID = nil
        current = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// The listener's chosen English voice when there is one, otherwise an American English voice,
    /// otherwise any English voice on the device. Nil when the device has no English voice.
    static func englishVoice() -> AVSpeechSynthesisVoice? {
        for code in ListenMeaningText.voiceLanguages(preferred: Locale.preferredLanguages) {
            if let voice = AVSpeechSynthesisVoice(language: code), ListenMeaningText.isEnglish(voice.language) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice.speechVoices().first { ListenMeaningText.isEnglish($0.language) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finished(id)
        }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard id == currentID, let completion else { return }
        self.completion = nil
        currentID = nil
        current = nil
        completion()
    }
}

/// Silent: records what it was asked to read. Tests end a reading with `finish()`.
/// With `finishesAfter` (used under `-FSFakeListen`) a reading ends by itself after that many
/// seconds, so screenshots can show the meaning line without any sound.
@MainActor
final class SimulatedMeaningSpeaker: MeaningSpeaking {
    private(set) var spoken: [String] = []
    private(set) var stopCount = 0
    private(set) var isSpeaking = false

    private let finishesAfter: Double?
    private var completion: (@MainActor () -> Void)?
    private var generation = 0

    init(finishesAfter: Double? = nil) {
        self.finishesAfter = finishesAfter
    }

    func speak(_ text: String, completion: @escaping @MainActor () -> Void) {
        generation += 1
        spoken.append(text)
        isSpeaking = true
        self.completion = completion
        guard let finishesAfter else { return }
        let token = generation
        let nanoseconds = UInt64(max(0, finishesAfter) * 1_000_000_000)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, self.generation == token else { return }
            self.finish()
        }
    }

    func stop() {
        generation += 1
        stopCount += 1
        isSpeaking = false
        completion = nil
    }

    /// Ends the current reading as if the voice had finished.
    func finish() {
        guard isSpeaking, let completion else { return }
        isSpeaking = false
        self.completion = nil
        completion()
    }
}
