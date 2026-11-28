import XCTest
@testable import FiveSkies

/// The transliteration (D6): found in the translation catalog, kept out of the picker,
/// stored apart from the translations, with its own saved switch and the 7 day refresh rule.
/// Only made up text is used ("sample line").
final class TransliterationTests: XCTestCase {
    private static let day: TimeInterval = 24 * 60 * 60
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static let catalogPath = "/api/v4/resources/translations"

    private var root: URL!
    private var translationStorage: TranslationStorage!
    private var transliterationStorage: TranslationStorage!
    private var translationEngine: TranslationSyncEngine!
    private var transliterationEngine: TranslationSyncEngine!
    private var relay: FakeRelay!
    private var clock: TestClock!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransliterationTests-\(UUID().uuidString)", isDirectory: true)
        translationStorage = TranslationStorage(directory: root.appendingPathComponent("Translations", isDirectory: true))
        transliterationStorage = TranslationStorage(directory: root.appendingPathComponent("Transliteration", isDirectory: true))
        relay = FakeRelay()
        clock = TestClock(Self.start)
        let testClock: TestClock = clock
        translationEngine = TranslationSyncEngine(client: relay, storage: translationStorage, now: { testClock.now })
        transliterationEngine = TranslationSyncEngine(client: relay, storage: transliterationStorage, now: { testClock.now })
        suiteName = "TransliterationTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        translationEngine = nil
        transliterationEngine = nil
        relay = nil
        defaults = nil
    }

    private func makeStore() -> TranslationStore {
        let testClock: TestClock = clock
        return TranslationStore(
            client: relay,
            engine: translationEngine,
            transliterationEngine: transliterationEngine,
            defaults: defaults,
            now: { testClock.now },
            autostart: false
        )
    }

    // MARK: - Canned JSON, shaped like the documented answers

    private static let catalogJSON = """
    {"translations":[\
    {"id":20,"name":"Sample Translation","author_name":"Sample Translator","slug":"sample-translation",\
    "language_name":"english","translated_name":null},\
    {"id":57,"name":"Transliteration","author_name":null,"slug":null,"language_name":"english",\
    "translated_name":{"name":"Transliteration","language_name":"english"}},\
    {"id":30,"name":"Sample Other","author_name":null,"slug":null,"language_name":"bosnian","translated_name":null}\
    ]}
    """

    private static func bootstrapPath(_ id: Int) -> String {
        "/api/v4/resources/sync?bootstrap=true&resources=translations:\(id)&per_page=100"
    }

    private static func incrementalPath(_ id: Int, token: String) -> String {
        "/api/v4/resources/sync?resources=translations:\(id)&sync_token=\(token)&per_page=100"
    }

    private static func snapshotPath(_ id: Int) -> String {
        "/api/v4/resources/snapshots/translations/\(id)"
    }

    private static func page(id: Int, token: String, create: Bool) -> String {
        var mutations = ""
        if create {
            mutations = "{\"sequence\":1,\"type\":\"RESOURCE_CREATE\",\"resource_group\":\"translations\","
                + "\"resource_id\":\(id),\"record_type\":null,\"record_key\":null,\"data\":null,"
                + "\"snapshot_url\":\"\(snapshotPath(id))\"}"
        }
        return """
        {"sync":{"sync_until_sequence":900,"has_more":false,"next_page_url":null,\
        "next_sync_token":"\(token)","mutations":[\(mutations)]}}
        """
    }

    private static func snapshot(id: Int, prefix: String) -> String {
        """
        {"resource_group":"translations","resource_id":\(id),"resource_content_id":\(id),"schema_version":1,\
        "sync_sequence":900,"records":[\
        {"id":\(id * 100 + 1),"verse_key":"1:1","text":"\(prefix) 1"},\
        {"id":\(id * 100 + 2),"verse_key":"1:2","text":"\(prefix) 2"}]}
        """
    }

    private func serveResource(_ id: Int, prefix: String, token: String) {
        relay.serve(Self.bootstrapPath(id), json: Self.page(id: id, token: token, create: true))
        relay.serve(Self.snapshotPath(id), json: Self.snapshot(id: id, prefix: prefix))
    }

    private func serveCatalogAndTransliteration() {
        relay.serve(Self.catalogPath, json: Self.catalogJSON)
        serveResource(57, prefix: "sample line", token: "sample-token-57")
    }

    private let translationInfo = TranslationInfo(id: 20, name: "Sample Translation", authorName: "Sample Translator", languageName: "english")
    private let transliterationInfo = TranslationInfo(id: 57, name: "Transliteration", authorName: nil, languageName: "english")

    // MARK: - Catalog detection

    func testDetectsTransliterationByNameOrSlug() {
        let byName = TranslationInfo(id: 57, name: "Transliteration", authorName: nil, languageName: "english")
        let bySlug = TranslationInfo(id: 91, name: "Sample Latin Letters", authorName: nil, slug: "en-transliteration", languageName: "english")
        let plain = TranslationInfo(id: 20, name: "Sample Translation", authorName: nil, slug: "sample", languageName: "english")

        XCTAssertTrue(TranslationText.isTransliteration(byName))
        XCTAssertTrue(TranslationText.isTransliteration(bySlug))
        XCTAssertFalse(TranslationText.isTransliteration(plain))
        XCTAssertEqual(TranslationText.transliterationEntry(in: [plain, byName])?.id, 57)
        XCTAssertEqual(TranslationText.transliterationEntry(in: [plain, bySlug])?.id, 91)
        XCTAssertNil(TranslationText.transliterationEntry(in: [plain]))
        XCTAssertNil(TranslationText.transliterationEntry(in: []))
    }

    func testIdAloneIsNeverEnoughAndEnglishThenKnownIdWins() {
        let idOnly = TranslationInfo(id: 57, name: "Sample Translation", authorName: nil, languageName: "english")
        XCTAssertNil(TranslationText.transliterationEntry(in: [idOnly]), "Id 57 counts only with translit in the name")

        let foreign = TranslationInfo(id: 12, name: "Sample transliteration", authorName: nil, languageName: "french")
        let englishOther = TranslationInfo(id: 70, name: "Sample Transliteration", authorName: nil, languageName: "english")
        let englishKnown = TranslationInfo(id: 57, name: "Transliteration", authorName: nil, languageName: "english")
        let englishLater = TranslationInfo(id: 80, name: "Transliteration Sample", authorName: nil, languageName: "english")

        XCTAssertEqual(TranslationText.transliterationEntry(in: [foreign, englishOther, englishKnown])?.id, 57)
        XCTAssertEqual(TranslationText.transliterationEntry(in: [foreign, englishLater, englishOther])?.id, 70)
        XCTAssertEqual(TranslationText.transliterationEntry(in: [foreign])?.id, 12)
    }

    // MARK: - Picker list

    func testPickerCatalogExcludesTransliteration() {
        let catalog = [
            TranslationInfo(id: 20, name: "Sample Translation", authorName: nil, languageName: "english"),
            TranslationInfo(id: 57, name: "Transliteration", authorName: nil, languageName: "english"),
            TranslationInfo(id: 91, name: "Sample", authorName: nil, slug: "sample-transliteration", languageName: "english")
        ]
        XCTAssertEqual(TranslationText.pickerCatalog(catalog).map(\.id), [20])
    }

    @MainActor
    func testStoreCatalogLeavesTransliterationOutOfThePicker() async {
        relay.serve(Self.catalogPath, json: Self.catalogJSON)
        let store = makeStore()
        await store.loadCatalog()

        XCTAssertEqual(store.catalogState, .loaded)
        XCTAssertEqual(store.catalog.map(\.id).sorted(), [20, 30])
        XCTAssertEqual(store.transliterationInfo?.id, 57)
        let pickerIDs = TranslationText.groupedByLanguage(store.catalog).flatMap { $0.translations.map(\.id) }
        XCTAssertFalse(pickerIDs.contains(57))
        XCTAssertEqual(store.transliterationSource, "Quran Foundation")
    }

    // MARK: - Separate storage

    @MainActor
    func testTransliterationIsStoredApartFromTheSelectedTranslation() async throws {
        serveResource(20, prefix: "sample text", token: "sample-token-20")
        _ = try await translationEngine.download(translationInfo)
        defaults.set(20, forKey: TranslationStore.selectedIDKey)
        serveCatalogAndTransliteration()

        let store = makeStore()
        await store.start()
        XCTAssertNil(store.transliteration(for: 1, aya: 1))

        store.showsTransliteration = true
        await store.ensureTransliteration()

        // Two folders, one copy each.
        XCTAssertNotNil(transliterationStorage.load(id: 57))
        XCTAssertNil(transliterationStorage.load(id: 20))
        XCTAssertNotNil(translationStorage.load(id: 20))
        XCTAssertNil(translationStorage.load(id: 57))

        XCTAssertEqual(store.downloaded.map(\.id), [20])
        XCTAssertEqual(store.selectedID, 20)
        XCTAssertEqual(defaults.integer(forKey: TranslationStore.selectedIDKey), 20)
        XCTAssertEqual(store.transliterationSummary?.id, 57)
        XCTAssertEqual(store.transliteration(for: 1, aya: 1), "sample line 1")
        XCTAssertEqual(store.transliteration(for: 1, aya: 2), "sample line 2")
        XCTAssertEqual(store.text(for: 1, aya: 1), "sample text 1")
        XCTAssertEqual(store.transliterationAttribution, "Transliteration provided by Quran Foundation.")

        // Off hides it but keeps the copy for offline use.
        store.showsTransliteration = false
        XCTAssertNil(store.transliteration(for: 1, aya: 1))
        XCTAssertNil(store.transliterationAttribution)
        XCTAssertNotNil(transliterationStorage.load(id: 57))

        // Removing the transliteration leaves the translation alone.
        store.showsTransliteration = true
        await store.ensureTransliteration()
        await store.removeTransliteration()
        XCTAssertNil(transliterationStorage.load(id: 57))
        XCTAssertNotNil(translationStorage.load(id: 20))
        XCTAssertNil(store.transliterationSummary)
        XCTAssertFalse(store.showsTransliteration)
        XCTAssertFalse(defaults.bool(forKey: TranslationStore.transliterationOnKey))
        XCTAssertEqual(store.text(for: 1, aya: 1), "sample text 1")
        XCTAssertEqual(store.selectedID, 20)
    }

    @MainActor
    func testTransliterationSavedAsATranslationIsTakenOutOfTheList() async throws {
        // An earlier build could save it among the translations and select it.
        serveResource(57, prefix: "sample line", token: "sample-token-57")
        _ = try await translationEngine.download(transliterationInfo)
        defaults.set(57, forKey: TranslationStore.selectedIDKey)

        let store = makeStore()
        await store.start()

        XCTAssertTrue(store.downloaded.isEmpty)
        XCTAssertNil(store.selectedID)
        XCTAssertNil(defaults.object(forKey: TranslationStore.selectedIDKey))
        XCTAssertNil(translationStorage.load(id: 57))
    }

    // MARK: - Switch

    @MainActor
    func testSwitchIsOffByDefaultAndPersists() {
        XCTAssertEqual(TranslationStore.transliterationOnKey, "transliterationOn")
        let first = TranslationStore(client: nil, engine: nil, defaults: defaults, autostart: false)
        XCTAssertFalse(first.showsTransliteration)

        first.showsTransliteration = true
        XCTAssertTrue(defaults.bool(forKey: "transliterationOn"))

        let second = TranslationStore(client: nil, engine: nil, defaults: defaults, autostart: false)
        XCTAssertTrue(second.showsTransliteration)

        second.showsTransliteration = false
        XCTAssertFalse(defaults.bool(forKey: "transliterationOn"))
        let third = TranslationStore(client: nil, engine: nil, defaults: defaults, autostart: false)
        XCTAssertFalse(third.showsTransliteration)
    }

    @MainActor
    func testSwitchOnWithoutRelayMakesNoRequests() async {
        let store = TranslationStore(client: nil, engine: nil, defaults: defaults, autostart: false)
        store.showsTransliteration = true
        await store.ensureTransliteration()
        XCTAssertNil(store.transliteration(for: 1, aya: 1))
        XCTAssertTrue(relay.requested.isEmpty)
        XCTAssertFalse(store.isConnected)
    }

    // MARK: - Seven day rule and offline

    @MainActor
    func testRefreshIsDueAfterSevenDaysAndOfflineKeepsTheCopy() async throws {
        defaults.set(true, forKey: TranslationStore.transliterationOnKey)
        serveCatalogAndTransliteration()
        let store = makeStore()
        await store.start()

        XCTAssertEqual(store.transliterationSummary?.lastSyncedAt, Self.start)
        XCTAssertEqual(store.transliteration(for: 1, aya: 1), "sample line 1")
        let afterDownload = relay.requested.count

        clock.now = Self.start.addingTimeInterval(6 * Self.day)
        XCTAssertFalse(store.transliterationNeedsRefresh)
        await store.readerOpened()
        XCTAssertEqual(relay.requested.count, afterDownload, "No request while the copy is fresh")

        clock.now = Self.start.addingTimeInterval(7 * Self.day)
        XCTAssertFalse(store.transliterationNeedsRefresh, "Exactly seven days is still fresh")

        // Offline at day 8: the sync fails and the copy stays readable.
        clock.now = Self.start.addingTimeInterval(8 * Self.day)
        XCTAssertTrue(store.transliterationNeedsRefresh)
        await store.readerOpened()
        XCTAssertEqual(relay.requested.last, Self.incrementalPath(57, token: "sample-token-57"))
        XCTAssertEqual(store.transliterationActivity, .failed(RelayError.transport.userMessage))
        XCTAssertEqual(store.transliteration(for: 1, aya: 1), "sample line 1")
        XCTAssertEqual(transliterationStorage.load(id: 57)?.syncToken, "sample-token-57")

        // Back online: the refresh runs and the copy is fresh again.
        relay.serve(Self.incrementalPath(57, token: "sample-token-57"), json: Self.page(id: 57, token: "sample-token-57b", create: false))
        await store.readerOpened()
        XCTAssertNil(store.transliterationActivity)
        XCTAssertFalse(store.transliterationNeedsRefresh)
        XCTAssertEqual(store.transliterationSummary?.lastSyncedAt, Self.start.addingTimeInterval(8 * Self.day))
        XCTAssertEqual(transliterationStorage.load(id: 57)?.syncToken, "sample-token-57b")
        XCTAssertEqual(store.transliteration(for: 1, aya: 2), "sample line 2")
    }

    // MARK: - Attribution

    func testAttributionAndSource() {
        XCTAssertEqual(
            TranslationText.transliterationAttribution(name: "Transliteration", authorName: nil),
            "Transliteration provided by Quran Foundation."
        )
        XCTAssertEqual(
            TranslationText.transliterationAttribution(name: "Transliteration", authorName: "Sample Author"),
            "Transliteration by Sample Author. Provided by Quran Foundation."
        )
        XCTAssertEqual(
            TranslationText.transliterationAttribution(name: "Sample Latin", authorName: " "),
            "Transliteration: Sample Latin. Provided by Quran Foundation."
        )
        XCTAssertEqual(TranslationText.transliterationSource(name: "Transliteration", authorName: nil), "Quran Foundation")
        XCTAssertEqual(
            TranslationText.transliterationSource(name: "Sample Latin", authorName: "Sample Author"),
            "Sample Latin, Sample Author, Quran Foundation"
        )
    }
}
