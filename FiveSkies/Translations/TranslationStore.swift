import Foundation

/// The translation feature for the views: the catalog, downloaded copies, the selected
/// translation and its text, and the download, remove and refresh actions.
/// Published values change only on the main actor.
final class TranslationStore: ObservableObject {
    static let selectedIDKey = "translationSelectedID"

    enum CatalogState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Activity: Equatable {
        case downloading(Double)
        case refreshing
        case failed(String)
    }

    /// The selected translation, in memory, ready for display.
    struct Loaded: Equatable {
        let summary: TranslationSummary
        /// `verse_key` to display text (footnote markers removed, nothing else changed).
        let verses: [String: String]
    }

    /// The available translations from the relay, kept in memory only.
    @Published private(set) var catalog: [TranslationInfo] = []
    @Published private(set) var catalogState: CatalogState = .idle
    @Published private(set) var downloaded: [TranslationSummary] = []
    @Published private(set) var activity: [Int: Activity] = [:]
    @Published private(set) var selectedID: Int?
    @Published private(set) var loaded: Loaded?

    /// False when no relay is configured: the feature makes no network calls.
    let isConnected: Bool

    private let client: RelayFetching?
    private let engine: TranslationSyncEngine?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var hasStarted = false

    init(
        client: RelayFetching?,
        engine: TranslationSyncEngine?,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        autostart: Bool = true
    ) {
        self.client = client
        self.engine = engine
        self.defaults = defaults
        self.now = now
        self.isConnected = client != nil && engine != nil
        selectedID = defaults.object(forKey: Self.selectedIDKey) as? Int
        if autostart {
            Task { @MainActor [weak self] in
                await self?.start()
            }
        }
    }

    /// The store the app uses. With `-FSFixedPhase` or inside the unit test host it does nothing at all.
    /// Without `FSRelayBaseURL` it shows copies already on the device but never calls the network.
    static func live() -> TranslationStore {
        guard RelayConfig.networkAllowed() else {
            return TranslationStore(client: nil, engine: nil, autostart: false)
        }
        let client: RelayFetching? = RelayConfig.fromBundle().map { RelayClient(config: $0) }
        let engine = TranslationStorage.defaultDirectory().map {
            TranslationSyncEngine(client: client, storage: TranslationStorage(directory: $0))
        }
        return TranslationStore(client: client, engine: engine)
    }

    // MARK: - Reading

    /// The selected translation's display text for an ayah, if it is loaded.
    func text(for sura: Int, aya: Int) -> String? {
        loaded?.verses["\(sura):\(aya)"]
    }

    /// The translation to suggest when nothing is selected yet.
    var suggestion: TranslationInfo? {
        selectedID == nil ? TranslationText.suggestion(in: catalog) : nil
    }

    func isDownloaded(_ id: Int) -> Bool {
        downloaded.contains { $0.id == id }
    }

    func summary(for id: Int) -> TranslationSummary? {
        downloaded.first { $0.id == id }
    }

    /// True when the copy is more than 7 days old and should be refreshed.
    func needsRefresh(_ summary: TranslationSummary) -> Bool {
        summary.needsRefresh(now: now())
    }

    // MARK: - Lifecycle

    /// Loads what is on the device, then refreshes stale copies. Runs once, at launch.
    @MainActor
    func start() async {
        guard !hasStarted, let engine else { return }
        hasStarted = true
        downloaded = await engine.summaries()
        if let id = selectedID, !isDownloaded(id) {
            select(nil)
        }
        await loadSelected()
        guard isConnected else { return }
        for id in await engine.staleIDs() {
            await refresh(id: id)
        }
    }

    /// Called when the reader opens: refreshes the selected copy if it is due.
    @MainActor
    func readerOpened() async {
        await start()
        guard isConnected, let engine, let id = selectedID else { return }
        if await engine.needsRefresh(id: id) {
            await refresh(id: id)
        }
    }

    // MARK: - Catalog

    @MainActor
    func loadCatalog(force: Bool = false) async {
        guard let client else { return }
        if catalogState == .loading { return }
        if !force, catalogState == .loaded { return }
        catalogState = .loading
        do {
            catalog = try await client.listTranslations()
            catalogState = .loaded
        } catch {
            catalogState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Actions

    @MainActor
    func select(_ id: Int?) {
        guard id != selectedID else { return }
        selectedID = id
        if let id {
            defaults.set(id, forKey: Self.selectedIDKey)
        } else {
            defaults.removeObject(forKey: Self.selectedIDKey)
        }
        loaded = nil
        Task { @MainActor [weak self] in
            await self?.loadSelected()
        }
    }

    @MainActor
    func download(_ info: TranslationInfo) {
        guard isConnected, let engine, !isBusy(info.id) else { return }
        let id = info.id
        activity[id] = .downloading(0)
        Task { @MainActor [weak self] in
            do {
                let outcome = try await engine.download(info) { value in
                    Task { @MainActor [weak self] in
                        self?.setProgress(value, for: id)
                    }
                }
                guard let self else { return }
                self.activity[id] = nil
                await self.handle(outcome)
                if self.selectedID == nil, self.isDownloaded(id) {
                    self.select(id)
                }
            } catch {
                self?.activity[id] = .failed(Self.message(for: error))
            }
        }
    }

    /// Syncs one downloaded translation now. On failure the copy on the device stays.
    @MainActor
    func refresh(id: Int) async {
        guard isConnected, let engine, !isBusy(id) else { return }
        activity[id] = .refreshing
        do {
            let outcome = try await engine.sync(id: id)
            activity[id] = nil
            await handle(outcome)
        } catch {
            activity[id] = .failed(Self.message(for: error))
        }
    }

    /// Deletes the copy on the device.
    @MainActor
    func remove(id: Int) {
        guard let engine, !isBusy(id) else { return }
        Task { @MainActor [weak self] in
            do {
                try await engine.remove(id: id)
                guard let self else { return }
                self.activity[id] = nil
                self.downloaded.removeAll { $0.id == id }
                if self.selectedID == id {
                    self.select(nil)
                }
            } catch {
                self?.activity[id] = .failed("Could not remove the translation. Try again.")
            }
        }
    }

    // MARK: - Private

    private func isBusy(_ id: Int) -> Bool {
        switch activity[id] {
        case .some(.downloading), .some(.refreshing):
            return true
        case .some(.failed), .none:
            return false
        }
    }

    @MainActor
    private func setProgress(_ value: Double, for id: Int) {
        guard case .some(.downloading) = activity[id] else { return }
        activity[id] = .downloading(min(max(value, 0), 1))
    }

    @MainActor
    private func handle(_ outcome: TranslationSyncOutcome) async {
        switch outcome {
        case .updated(let summary):
            if let index = downloaded.firstIndex(where: { $0.id == summary.id }) {
                downloaded[index] = summary
            } else {
                downloaded.append(summary)
                downloaded.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            if summary.id == selectedID {
                await loadSelected()
            }
        case .removed(let id):
            downloaded.removeAll { $0.id == id }
            if selectedID == id {
                select(nil)
            }
        }
    }

    @MainActor
    private func loadSelected() async {
        guard let engine, let id = selectedID else {
            loaded = nil
            return
        }
        let result = await engine.displayCopy(id: id)
        // The selection may have changed while loading.
        guard selectedID == id else { return }
        if let result {
            loaded = Loaded(summary: result.summary, verses: result.verses)
        } else {
            loaded = nil
        }
    }

    static func message(for error: Error) -> String {
        if let relay = error as? RelayError {
            return relay.userMessage
        }
        if let sync = error as? TranslationSyncError {
            switch sync {
            case .notConnected:
                return "Translations will be available soon."
            case .notDownloaded:
                return "Download this translation first."
            case .malformed, .empty:
                return "The translation could not be read. Try again later."
            }
        }
        return "Something went wrong. Try again."
    }
}

extension TranslationSyncEngine {
    /// The stored copy as display text, built off the main thread.
    func displayCopy(id: Int) -> (summary: TranslationSummary, verses: [String: String])? {
        guard let stored = load(id: id) else { return nil }
        let verses = stored.versesByKey().mapValues { TranslationText.removingFootnotes($0) }
        return (stored.summary, verses)
    }
}
