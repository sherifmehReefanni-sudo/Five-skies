import Foundation

/// The translation feature for the views: the catalog, downloaded copies, the selected
/// translation and its text, and the download, remove and refresh actions.
/// It also keeps the transliteration (D6): its own text with its own switch, synced through
/// Content Sync like a translation but stored in its own folder and never offered as a translation.
/// Published values change only on the main actor.
final class TranslationStore: ObservableObject {
    static let selectedIDKey = "translationSelectedID"
    static let transliterationOnKey = "transliterationOn"

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

    /// The available translations from the relay, kept in memory only. Never holds the transliteration.
    @Published private(set) var catalog: [TranslationInfo] = []
    @Published private(set) var catalogState: CatalogState = .idle
    @Published private(set) var downloaded: [TranslationSummary] = []
    @Published private(set) var activity: [Int: Activity] = [:]
    @Published private(set) var selectedID: Int?
    @Published private(set) var loaded: Loaded?

    // Transliteration

    /// The transliteration entry of the catalog, once the catalog is loaded.
    @Published private(set) var transliterationInfo: TranslationInfo?
    /// The transliteration copy on the device, if any.
    @Published private(set) var transliterationSummary: TranslationSummary?
    /// The transliteration text in memory. Loaded only while it is switched on.
    @Published private(set) var transliterationLoaded: Loaded?
    @Published private(set) var transliterationActivity: Activity?
    /// The person's switch, saved under "transliterationOn". Off by default.
    /// Turning it on downloads the transliteration if it is not on the device yet.
    @Published var showsTransliteration: Bool = false {
        didSet {
            guard showsTransliteration != oldValue else { return }
            defaults.set(showsTransliteration, forKey: Self.transliterationOnKey)
            Task { @MainActor [weak self] in
                await self?.transliterationSwitchChanged()
            }
        }
    }

    /// False when no relay is configured: the feature makes no network calls.
    let isConnected: Bool

    private let client: RelayFetching?
    private let engine: TranslationSyncEngine?
    private let transliterationEngine: TranslationSyncEngine?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var hasStarted = false
    private var transliterationTask: Task<Void, Never>?

    /// `engine` keeps the translations; `transliterationEngine` keeps the transliteration
    /// in a storage of its own (see `TranslationStorage.transliterationDirectory()`).
    init(
        client: RelayFetching?,
        engine: TranslationSyncEngine?,
        transliterationEngine: TranslationSyncEngine? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        autostart: Bool = true
    ) {
        self.client = client
        self.engine = engine
        self.transliterationEngine = transliterationEngine
        self.defaults = defaults
        self.now = now
        self.isConnected = client != nil && engine != nil
        selectedID = defaults.object(forKey: Self.selectedIDKey) as? Int
        showsTransliteration = defaults.bool(forKey: Self.transliterationOnKey)
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
        let transliterationEngine = TranslationStorage.transliterationDirectory().map {
            TranslationSyncEngine(client: client, storage: TranslationStorage(directory: $0))
        }
        return TranslationStore(client: client, engine: engine, transliterationEngine: transliterationEngine)
    }

    // MARK: - Reading

    /// The selected translation's display text for an ayah, if it is loaded.
    func text(for sura: Int, aya: Int) -> String? {
        loaded?.verses["\(sura):\(aya)"]
    }

    /// The transliteration of an ayah, only while the switch is on and the copy is loaded.
    func transliteration(for sura: Int, aya: Int) -> String? {
        guard showsTransliteration else { return nil }
        return transliterationLoaded?.verses["\(sura):\(aya)"]
    }

    /// The footer line for the transliteration, for example
    /// "Transliteration provided by Quran Foundation." Nil when it is off or not loaded.
    var transliterationAttribution: String? {
        guard showsTransliteration, let summary = transliterationLoaded?.summary else { return nil }
        return TranslationText.transliterationAttribution(name: summary.name, authorName: summary.authorName)
    }

    /// The short source under the switch, for example "Quran Foundation".
    var transliterationSource: String? {
        if let summary = transliterationSummary {
            return TranslationText.transliterationSource(name: summary.name, authorName: summary.authorName)
        }
        if let info = transliterationInfo {
            return TranslationText.transliterationSource(name: info.name, authorName: info.authorName)
        }
        return nil
    }

    /// True when the transliteration copy is more than 7 days old.
    var transliterationNeedsRefresh: Bool {
        transliterationSummary.map { needsRefresh($0) } ?? false
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
        let stored = await engine.summaries()
        let misfiled = stored.filter { TranslationText.isTransliteration(name: $0.name, slug: nil) }
        downloaded = stored.filter { !TranslationText.isTransliteration(name: $0.name, slug: nil) }
        if transliterationEngine != nil {
            // An earlier build let the transliteration be picked as a translation. That copy
            // now lives in the transliteration storage, so the old one is deleted.
            for summary in misfiled {
                try? await engine.remove(id: summary.id)
            }
        }
        if let id = selectedID, !isDownloaded(id) {
            select(nil)
        }
        await loadSelected()
        await loadTransliterationFromDevice()
        guard isConnected else { return }
        for id in await engine.staleIDs() where isDownloaded(id) {
            await refresh(id: id)
        }
        if transliterationNeedsRefresh {
            await refreshTransliteration()
        }
        if showsTransliteration, transliterationSummary == nil {
            await ensureTransliteration()
        }
    }

    /// Called when the reader opens: refreshes the selected copy and the transliteration if due.
    @MainActor
    func readerOpened() async {
        await start()
        guard isConnected else { return }
        if let engine, let id = selectedID {
            if await engine.needsRefresh(id: id) {
                await refresh(id: id)
            }
        }
        if transliterationNeedsRefresh {
            await refreshTransliteration()
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
            let all = try await client.listTranslations()
            catalog = TranslationText.pickerCatalog(all)
            transliterationInfo = TranslationText.transliterationEntry(in: all)
            catalogState = .loaded
            if showsTransliteration, transliterationSummary == nil, transliterationTask == nil {
                // The switch was turned on while the catalog was still loading.
                Task { @MainActor [weak self] in
                    await self?.ensureTransliteration()
                }
            }
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

    // MARK: - Transliteration actions

    /// With the switch on: loads the copy on the device, or downloads it when there is none.
    /// A second caller waits for the run already going.
    @MainActor
    func ensureTransliteration() async {
        if let running = transliterationTask {
            await running.value
            return
        }
        let task = Task { @MainActor [weak self] in
            await self?.performEnsureTransliteration()
            // Cleared inside the task, so no one sees a finished task as running.
            self?.transliterationTask = nil
        }
        transliterationTask = task
        await task.value
    }

    /// Syncs the transliteration now. On failure the copy on the device stays.
    @MainActor
    func refreshTransliteration() async {
        guard isConnected, let store = transliterationEngine, let id = transliterationSummary?.id,
              !isTransliterationBusy
        else { return }
        transliterationActivity = .refreshing
        do {
            let outcome = try await store.sync(id: id)
            transliterationActivity = nil
            await handleTransliteration(outcome)
        } catch {
            transliterationActivity = .failed(Self.message(for: error))
        }
    }

    /// Deletes the transliteration copy and turns the switch off. Translations are not touched.
    @MainActor
    func removeTransliteration() async {
        guard let store = transliterationEngine, let id = transliterationSummary?.id, !isTransliterationBusy else {
            return
        }
        do {
            try await store.remove(id: id)
            transliterationActivity = nil
            transliterationSummary = nil
            transliterationLoaded = nil
            showsTransliteration = false
        } catch {
            transliterationActivity = .failed("Could not remove the transliteration. Try again.")
        }
    }

    // MARK: - Private

    private var isTransliterationBusy: Bool {
        switch transliterationActivity {
        case .some(.downloading), .some(.refreshing):
            return true
        case .some(.failed), .none:
            return false
        }
    }

    @MainActor
    private func transliterationSwitchChanged() async {
        if showsTransliteration {
            await ensureTransliteration()
        } else {
            transliterationLoaded = nil
            if case .some(.failed) = transliterationActivity {
                transliterationActivity = nil
            }
        }
    }

    @MainActor
    private func performEnsureTransliteration() async {
        guard showsTransliteration, let store = transliterationEngine else { return }
        if transliterationSummary == nil {
            transliterationSummary = await store.summaries().first
        }
        if transliterationSummary != nil {
            if transliterationLoaded == nil {
                await loadTransliterationText()
            }
            return
        }
        guard isConnected, !isTransliterationBusy else { return }
        if transliterationInfo == nil {
            await loadCatalog()
        }
        guard let info = transliterationInfo else {
            switch catalogState {
            case .loaded:
                transliterationActivity = .failed("Transliteration is not offered right now.")
            case .failed(let text):
                transliterationActivity = .failed(text)
            case .idle, .loading:
                // The catalog is loading elsewhere; `loadCatalog` starts the download when it is done.
                break
            }
            return
        }
        transliterationActivity = .downloading(0)
        do {
            let outcome = try await store.download(info) { value in
                Task { @MainActor [weak self] in
                    self?.setTransliterationProgress(value)
                }
            }
            transliterationActivity = nil
            await handleTransliteration(outcome)
            // Keep a single transliteration on the device.
            for other in await store.summaries() where other.id != info.id {
                try? await store.remove(id: other.id)
            }
        } catch {
            transliterationActivity = .failed(Self.message(for: error))
        }
    }

    @MainActor
    private func setTransliterationProgress(_ value: Double) {
        guard case .some(.downloading) = transliterationActivity else { return }
        transliterationActivity = .downloading(min(max(value, 0), 1))
    }

    @MainActor
    private func handleTransliteration(_ outcome: TranslationSyncOutcome) async {
        switch outcome {
        case .updated(let summary):
            transliterationSummary = summary
            await loadTransliterationText()
        case .removed(let id):
            if transliterationSummary?.id == id {
                transliterationSummary = nil
                transliterationLoaded = nil
            }
        }
    }

    @MainActor
    private func loadTransliterationFromDevice() async {
        guard let store = transliterationEngine else { return }
        transliterationSummary = await store.summaries().first
        await loadTransliterationText()
    }

    @MainActor
    private func loadTransliterationText() async {
        guard showsTransliteration, let store = transliterationEngine, let id = transliterationSummary?.id else {
            transliterationLoaded = nil
            return
        }
        let result = await store.displayCopy(id: id)
        // The switch or the copy may have changed while loading.
        guard showsTransliteration, transliterationSummary?.id == id else { return }
        if let result {
            transliterationLoaded = Loaded(summary: result.summary, verses: result.verses)
        } else {
            transliterationLoaded = nil
        }
    }

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
