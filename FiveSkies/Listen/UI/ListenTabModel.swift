import Foundation

/// Where the reciter list stands.
enum ListenRecitersState: Equatable {
    case loading
    case loaded
    case failed
}

/// Why a tapped surah did not start, shown with a Retry button.
struct ListenPlayProblem: Equatable {
    enum Kind: Equatable {
        case noReciter
        case unavailable
    }

    let chapter: Int
    let chapterName: String
    let kind: Kind

    var message: String {
        switch kind {
        case .noReciter:
            return "Choose a reciter first, then tap a surah."
        case .unavailable:
            return "This surah could not load. Check your connection and try again."
        }
    }
}

/// The Listen tab's state: the reciter list, the chosen reciter, and the surah being looked up.
/// Audio itself is the player's job; this only finds the file and hands the player a `NowPlayingItem`.
final class ListenTabModel: ObservableObject {
    static let reciterKey = "listen.reciterID"

    @Published private(set) var recitersState: ListenRecitersState = .loading
    @Published private(set) var reciters: [Reciter] = []
    @Published private(set) var selectedReciter: Reciter? = nil
    /// The surah whose audio is being looked up right now, if any.
    @Published private(set) var fetchingChapter: Int? = nil
    @Published private(set) var problem: ListenPlayProblem? = nil

    private let catalog: any ListenCatalog
    private let defaults: UserDefaults
    private var loadTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?

    init(catalog: any ListenCatalog, defaults: UserDefaults = .standard) {
        self.catalog = catalog
        self.defaults = defaults
    }

    /// The reciter to show: the saved one when the list still has it, otherwise the first.
    static func resolveSelection(savedID: Int?, in reciters: [Reciter]) -> Reciter? {
        if let savedID, let saved = reciters.first(where: { $0.id == savedID }) {
            return saved
        }
        return reciters.first
    }

    var savedReciterID: Int? {
        defaults.object(forKey: Self.reciterKey) as? Int
    }

    /// Loads the reciters unless they are loaded or already loading.
    @MainActor
    func loadIfNeeded() {
        guard recitersState != .loaded, loadTask == nil else { return }
        reload()
    }

    /// Loads the reciters again, for Retry.
    @MainActor
    func reload() {
        loadTask?.cancel()
        recitersState = .loading
        let catalog = self.catalog
        loadTask = Task { @MainActor [weak self] in
            do {
                let list = try await catalog.reciters()
                guard !Task.isCancelled, let self else { return }
                self.apply(list)
                self.loadTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.recitersState = .failed
                self.loadTask = nil
            }
        }
    }

    /// Loads the reciters and waits for them. Used by tests.
    @MainActor
    func loadAndWait() async {
        reload()
        if let pending = loadTask {
            await pending.value
        }
    }

    @MainActor
    private func apply(_ list: [Reciter]) {
        reciters = list
        selectedReciter = Self.resolveSelection(savedID: savedReciterID, in: list)
        recitersState = .loaded
    }

    /// Chooses a reciter and remembers it. It is used for the next surah tapped.
    @MainActor
    func select(_ reciter: Reciter) {
        selectedReciter = reciter
        defaults.set(reciter.id, forKey: Self.reciterKey)
        if problem?.kind == .noReciter {
            problem = nil
        }
    }

    /// Looks up a surah for the chosen reciter and starts it. A newer tap replaces an older one.
    @MainActor
    func play(chapter: Int, name: String, on player: ListenPlayer) {
        audioTask?.cancel()
        problem = nil
        fetchingChapter = chapter
        let catalog = self.catalog
        audioTask = Task { @MainActor [weak self, weak player] in
            // A tap while the reciters are still loading waits for them.
            if let pending = self?.loadTask {
                await pending.value
            }
            guard !Task.isCancelled, let self else { return }
            guard let reciter = self.selectedReciter else {
                self.fetchingChapter = nil
                self.problem = ListenPlayProblem(chapter: chapter, chapterName: name, kind: .noReciter)
                return
            }
            do {
                let audio = try await catalog.chapterAudio(reciterID: reciter.id, chapter: chapter)
                guard !Task.isCancelled else { return }
                self.fetchingChapter = nil
                player?.play(NowPlayingItem(reciter: reciter, chapter: chapter, chapterName: name, audio: audio))
            } catch {
                guard !Task.isCancelled else { return }
                self.fetchingChapter = nil
                self.problem = ListenPlayProblem(chapter: chapter, chapterName: name, kind: .unavailable)
            }
        }
    }

    /// Tries the failed surah again. With no reciter, loads the reciters again first.
    @MainActor
    func retry(on player: ListenPlayer) {
        guard let problem else { return }
        if problem.kind == .noReciter, selectedReciter == nil {
            reload()
        }
        play(chapter: problem.chapter, name: problem.chapterName, on: player)
    }

    @MainActor
    func dismissProblem() {
        problem = nil
    }
}

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

/// The last sleep timer choice, kept by the Listen tab while the player sheet comes and goes.
struct ListenSleepChoice: Equatable {
    var option: ListenSleepOption = .off
    var chapter: Int?
}
