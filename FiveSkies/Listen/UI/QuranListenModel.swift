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
            return "Choose a reciter first, then tap play."
        case .unavailable:
            return "This surah could not load. Check your connection and try again."
        }
    }
}

/// The listening side of the Quran tab: the reciter list, the chosen reciter, and the surah
/// being looked up. Audio itself is the player's job; this only finds the file and hands the
/// player a `NowPlayingItem`.
final class QuranListenModel: ObservableObject {
    /// Same key as the B1 Listen tab, so the reciter people chose there is kept.
    static let reciterKey = "listen.reciterID"

    @Published private(set) var recitersState: ListenRecitersState = .loading
    @Published private(set) var reciters: [Reciter] = []
    @Published private(set) var selectedReciter: Reciter? = nil
    /// Plain words for the last reciter list failure.
    @Published private(set) var failureMessage: String? = nil
    /// The surah whose audio is being looked up right now, if any.
    @Published private(set) var fetchingChapter: Int? = nil
    @Published private(set) var problem: ListenPlayProblem? = nil

    let catalog: any ListenCatalog
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

    /// True while play buttons make sense: the reciters are loading, or one is chosen.
    var offersPlayback: Bool {
        recitersState == .loading || selectedReciter != nil
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
        failureMessage = nil
        let catalog = self.catalog
        loadTask = Task { @MainActor [weak self] in
            do {
                let list = try await catalog.reciters()
                guard !Task.isCancelled, let self else { return }
                self.apply(list)
                self.loadTask = nil
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.failureMessage = ListenCatalogError.from(error).userMessage
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

    /// Chooses a reciter and remembers it. It is used for the next surah played.
    @MainActor
    func select(_ reciter: Reciter) {
        selectedReciter = reciter
        defaults.set(reciter.id, forKey: Self.reciterKey)
        if problem?.kind == .noReciter {
            problem = nil
        }
    }

    /// Gives the player what it needs to move on to another surah by itself. Set once.
    @MainActor
    func connect(_ player: ListenPlayer, suras: [Sura]) {
        guard player.queueResolver == nil, !suras.isEmpty else { return }
        player.queueResolver = ListenCatalogQueueResolver(catalog: catalog, suras: suras)
    }

    /// True when `chapter` is the one in the player, with the chosen reciter.
    @MainActor
    func isCurrent(_ chapter: Int, in player: ListenPlayer) -> Bool {
        guard let item = player.item else { return false }
        return item.chapter == chapter && item.reciter.id == selectedReciter?.id
    }

    /// The play button on a surah: the current one toggles play and pause; anything else starts fresh.
    @MainActor
    func playOrToggle(chapter: Int, name: String, on player: ListenPlayer) {
        if isCurrent(chapter, in: player), player.state == .playing || player.state == .paused {
            player.togglePlayPause()
        } else {
            play(chapter: chapter, name: name, on: player)
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

/// Makes the item for another surah with the same reciter, from the catalog and the bundled
/// surah names (English letters only), so the player can play the next surah or a set.
struct ListenCatalogQueueResolver: ListenQueueResolving {
    let catalog: any ListenCatalog
    let names: [Int: String]

    init(catalog: any ListenCatalog, suras: [Sura]) {
        self.catalog = catalog
        var names: [Int: String] = [:]
        for sura in suras {
            names[sura.number] = sura.transliteratedName
        }
        self.names = names
    }

    func name(for chapter: Int) -> String {
        names[chapter] ?? "Surah \(chapter)"
    }

    func item(chapter: Int, reciter: Reciter) async throws -> NowPlayingItem {
        guard ListenSetRange.chapters.contains(chapter) else {
            throw ListenCatalogError.notFound
        }
        let audio = try await catalog.chapterAudio(reciterID: reciter.id, chapter: chapter)
        return NowPlayingItem(reciter: reciter, chapter: chapter, chapterName: name(for: chapter), audio: audio)
    }
}
