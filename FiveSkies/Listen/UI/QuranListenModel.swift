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
    /// The ayah the listener asked to start from, so Retry starts there too.
    var fromAyah: Int? = nil

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

    /// Looks up a surah for the chosen reciter and starts it, at `fromAyah` when one is given
    /// (the player starts at the beginning when it has no timings). A newer tap replaces an older one.
    @MainActor
    func play(chapter: Int, name: String, fromAyah: Int? = nil, on player: ListenPlayer) {
        audioTask?.cancel()
        problem = nil
        // Already in the player with the chosen reciter: jump there without looking it up again.
        if let fromAyah, loadTask == nil, isCurrent(chapter, in: player), let current = player.item {
            fetchingChapter = nil
            player.play(current, fromAyah: fromAyah)
            return
        }
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
                self.problem = ListenPlayProblem(chapter: chapter, chapterName: name, kind: .noReciter, fromAyah: fromAyah)
                return
            }
            do {
                let audio = try await catalog.chapterAudio(reciterID: reciter.id, chapter: chapter)
                guard !Task.isCancelled else { return }
                self.fetchingChapter = nil
                let item = NowPlayingItem(reciter: reciter, chapter: chapter, chapterName: name, audio: audio)
                if let fromAyah {
                    player?.play(item, fromAyah: fromAyah)
                } else {
                    player?.play(item)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.fetchingChapter = nil
                self.problem = ListenPlayProblem(chapter: chapter, chapterName: name, kind: .unavailable, fromAyah: fromAyah)
            }
        }
    }

    /// True only when "Play from this ayah" is known to start at the beginning: the player has
    /// no timings source at all, or this surah is loaded with the chosen reciter and has no timings.
    /// While a surah is still loading this stays false, since its timings may yet arrive.
    @MainActor
    func playFromAyahStartsAtBeginning(chapter: Int, in player: ListenPlayer) -> Bool {
        if player.timingProvider == nil {
            return true
        }
        guard isCurrent(chapter, in: player) else { return false }
        switch player.state {
        case .playing, .paused:
            return !player.timingsAvailable
        case .idle, .loading, .failed:
            return false
        }
    }

    /// The label of the ayah dialog's play button.
    static func playFromAyahTitle(startsAtBeginning: Bool) -> String {
        startsAtBeginning
            ? "Play from this ayah (starts at the beginning for this reciter)"
            : "Play from this ayah"
    }

    /// Tries the failed surah again. With no reciter, loads the reciters again first.
    @MainActor
    func retry(on player: ListenPlayer) {
        guard let problem else { return }
        if problem.kind == .noReciter, selectedReciter == nil {
            reload()
        }
        play(chapter: problem.chapter, name: problem.chapterName, fromAyah: problem.fromAyah, on: player)
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
