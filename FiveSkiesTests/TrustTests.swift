import XCTest
@testable import FiveSkies

/// A key-value store kept in memory. `dropsWrites` acts like a store that is not available.
private final class TrustFakeStore: BackupKeyValueStore {
    var values: [String: Data] = [:]
    var dropsWrites = false
    private(set) var synchronizeCount = 0

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func setData(_ data: Data, forKey key: String) {
        guard !dropsWrites else { return }
        values[key] = data
    }

    func removeValue(forKey key: String) {
        values[key] = nil
    }

    @discardableResult func synchronize() -> Bool {
        synchronizeCount += 1
        return true
    }
}

final class TrustTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames = []
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "TrustTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier))
    }

    /// 27 Nov 2026 at the given hour and minute, in UTC.
    private func utcDate(hour: Int, minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try zone("UTC")
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 27
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(calendar.date(from: components))
    }

    // MARK: - Greeting

    func testGreetingHourBoundaries() throws {
        let utc = try zone("UTC")
        let cases: [(Int, Int, String)] = [
            (0, 0, "Good evening, Sherif"),
            (3, 59, "Good evening, Sherif"),
            (4, 0, "Good morning, Sherif"),
            (11, 59, "Good morning, Sherif"),
            (12, 0, "Good afternoon, Sherif"),
            (16, 59, "Good afternoon, Sherif"),
            (17, 0, "Good evening, Sherif"),
            (23, 59, "Good evening, Sherif")
        ]
        for (hour, minute, expected) in cases {
            let now = try utcDate(hour: hour, minute: minute)
            XCTAssertEqual(
                GreetingText.make(firstName: "Sherif", now: now, timeZone: utc),
                expected,
                "at \(hour):\(minute)"
            )
        }
    }

    func testGreetingUsesTheGivenTimeZone() throws {
        let now = try utcDate(hour: 10)
        XCTAssertEqual(GreetingText.make(firstName: "Sherif", now: now, timeZone: try zone("UTC")), "Good morning, Sherif")
        // 05:00 in New York.
        XCTAssertEqual(GreetingText.make(firstName: "Sherif", now: now, timeZone: try zone("America/New_York")), "Good morning, Sherif")
        // 02:00 in Los Angeles.
        XCTAssertEqual(GreetingText.make(firstName: "Sherif", now: now, timeZone: try zone("America/Los_Angeles")), "Good evening, Sherif")
        // 13:00 in Riyadh.
        XCTAssertEqual(GreetingText.make(firstName: "Sherif", now: now, timeZone: try zone("Asia/Riyadh")), "Good afternoon, Sherif")
        // 19:00 in Tokyo.
        XCTAssertEqual(GreetingText.make(firstName: "Sherif", now: now, timeZone: try zone("Asia/Tokyo")), "Good evening, Sherif")
    }

    func testGreetingIsNilWithoutAName() throws {
        let now = try utcDate(hour: 9)
        let utc = try zone("UTC")
        XCTAssertNil(GreetingText.make(firstName: nil, now: now, timeZone: utc))
        XCTAssertNil(GreetingText.make(firstName: "", now: now, timeZone: utc))
        XCTAssertNil(GreetingText.make(firstName: "   \n ", now: now, timeZone: utc))
    }

    func testGreetingTrimsTheName() throws {
        let now = try utcDate(hour: 9)
        XCTAssertEqual(GreetingText.make(firstName: "  Sherif \n", now: now, timeZone: try zone("UTC")), "Good morning, Sherif")
    }

    func testNameNormalizeTrimsAndLimits() {
        XCTAssertEqual(FirstNameStore.normalize("  Reef  "), "Reef")
        XCTAssertNil(FirstNameStore.normalize(nil))
        XCTAssertNil(FirstNameStore.normalize("  "))

        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(FirstNameStore.normalize(long), String(repeating: "a", count: 30))

        // The cut lands on a space, so the result is trimmed again.
        let cutOnSpace = String(repeating: "b", count: 29) + " cdef"
        XCTAssertEqual(FirstNameStore.normalize(cutOnSpace), String(repeating: "b", count: 29))
    }

    func testNameSaveAndLoad() throws {
        let defaults = try makeDefaults()
        FirstNameStore.save("  Sherif ", to: defaults)
        XCTAssertEqual(defaults.string(forKey: FirstNameStore.storageKey), "Sherif")
        XCTAssertEqual(FirstNameStore.load(from: defaults), "Sherif")

        FirstNameStore.save("   ", to: defaults)
        XCTAssertNil(defaults.object(forKey: FirstNameStore.storageKey))
        XCTAssertNil(FirstNameStore.load(from: defaults))
    }

    // MARK: - Backup

    private let backupDate = Date(timeIntervalSince1970: 1_795_000_000)

    private func fillSource(_ defaults: UserDefaults) {
        defaults.set(Data([1, 2, 3]), forKey: "prayedByDay")
        defaults.set(Data([4, 5]), forKey: "tracker.pauses")
        defaults.set(["1448-09-01", "1448-09-02"], forKey: "ramadan.fastedDays")
        defaults.set(["1448-10-02"], forKey: "ramadan.voluntaryFasts")
        defaults.set(Data([6]), forKey: "memorizeProgress")
        defaults.set(Data([7, 8]), forKey: "quranBookmarks")
        defaults.set(Data([9]), forKey: "quranLastRead")
        defaults.set(34.0, forKey: "quranArabicTextSize")
        defaults.set("midnight", forKey: "appearance.skyTheme")
        defaults.set("egyptian", forKey: "settings.calculationMethod")
        defaults.set(-1, forKey: "settings.hijriAdjustment")
        defaults.set(true, forKey: "settings.nightAlarm.enabled")
        defaults.set([2, 5], forKey: "settings.nightAlarm.weekdays")
        defaults.set("silent", forKey: "settings.alertMode.fajr")
        defaults.set(33, forKey: "tasbih.count")
        defaults.set(false, forKey: "tasbih.haptics")
        defaults.set(Data([10]), forKey: "goals.list")

        // Not backed up.
        defaults.set("Sherif", forKey: "trust.firstName")
        defaults.set(85, forKey: "translationSelectedID")
        defaults.set(["0,0": "Makkah"], forKey: "placeName.cache")
        defaults.set(Data([11]), forKey: "widgets.sharedPrayerConfig")
    }

    func testBackupRoundTrip() throws {
        let source = try makeDefaults()
        let target = try makeDefaults()
        fillSource(source)
        let store = TrustFakeStore()
        let date = backupDate

        let backup = BackupService(defaults: source, store: store, now: { date })
        XCTAssertEqual(try backup.backUp(), date)
        XCTAssertEqual(backup.latestSnapshot()?.createdAt, date)
        XCTAssertEqual(backup.latestSnapshot()?.version, BackupService.currentVersion)

        let restorer = BackupService(defaults: target, store: store)
        XCTAssertEqual(restorer.latestSnapshot()?.createdAt, date)
        let restored = try restorer.restore()
        XCTAssertGreaterThanOrEqual(restored, 17)

        XCTAssertEqual(target.data(forKey: "prayedByDay"), Data([1, 2, 3]))
        XCTAssertEqual(target.data(forKey: "tracker.pauses"), Data([4, 5]))
        XCTAssertEqual(target.stringArray(forKey: "ramadan.fastedDays"), ["1448-09-01", "1448-09-02"])
        XCTAssertEqual(target.stringArray(forKey: "ramadan.voluntaryFasts"), ["1448-10-02"])
        XCTAssertEqual(target.data(forKey: "memorizeProgress"), Data([6]))
        XCTAssertEqual(target.data(forKey: "quranBookmarks"), Data([7, 8]))
        XCTAssertEqual(target.data(forKey: "quranLastRead"), Data([9]))
        XCTAssertEqual(target.double(forKey: "quranArabicTextSize"), 34.0)
        XCTAssertEqual(target.string(forKey: "appearance.skyTheme"), "midnight")
        XCTAssertEqual(target.string(forKey: "settings.calculationMethod"), "egyptian")
        XCTAssertEqual(target.object(forKey: "settings.hijriAdjustment") as? Int, -1)
        XCTAssertEqual(target.object(forKey: "settings.nightAlarm.enabled") as? Bool, true)
        XCTAssertEqual(target.array(forKey: "settings.nightAlarm.weekdays") as? [Int], [2, 5])
        XCTAssertEqual(target.string(forKey: "settings.alertMode.fajr"), "silent")
        XCTAssertEqual(target.object(forKey: "tasbih.count") as? Int, 33)
        XCTAssertEqual(target.object(forKey: "tasbih.haptics") as? Bool, false)
        XCTAssertEqual(target.data(forKey: "goals.list"), Data([10]))

        XCTAssertNil(target.object(forKey: "trust.firstName"))
        XCTAssertNil(target.object(forKey: "translationSelectedID"))
        XCTAssertNil(target.object(forKey: "placeName.cache"))
        XCTAssertNil(target.object(forKey: "widgets.sharedPrayerConfig"))
    }

    func testSnapshotExcludesPrivateAndSyncedKeys() throws {
        let source = try makeDefaults()
        fillSource(source)
        let snapshot = try BackupService(defaults: source, store: TrustFakeStore()).makeSnapshot()
        XCTAssertTrue(snapshot.keys.contains("prayedByDay"))
        XCTAssertTrue(snapshot.keys.contains("settings.nightAlarm.weekdays"))
        XCTAssertFalse(snapshot.keys.contains("trust.firstName"))
        XCTAssertFalse(snapshot.keys.contains("translationSelectedID"))
        XCTAssertFalse(snapshot.keys.contains("placeName.cache"))
        XCTAssertFalse(snapshot.keys.contains("widgets.sharedPrayerConfig"))
        XCTAssertEqual(snapshot.keys, snapshot.keys.sorted())
    }

    func testBackupIsJSONWithVersionAndDate() throws {
        let source = try makeDefaults()
        fillSource(source)
        let store = TrustFakeStore()
        let date = backupDate
        try BackupService(defaults: source, store: store, now: { date }).backUp()

        let data = try XCTUnwrap(store.values[BackupService.cloudKey])
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try XCTUnwrap(object as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNotNil(json["createdAt"] as? String)
        XCTAssertNotNil(json["payload"] as? String)
        XCTAssertGreaterThan(store.synchronizeCount, 0)
    }

    func testRestoreWithNoBackupThrows() throws {
        let service = BackupService(defaults: try makeDefaults(), store: TrustFakeStore())
        XCTAssertNil(service.latestSnapshot())
        XCTAssertThrowsError(try service.restore()) { error in
            XCTAssertEqual(error as? BackupError, .nothingToRestore)
        }
    }

    func testRestoreRejectsNewerVersion() throws {
        let store = TrustFakeStore()
        let payload = try PropertyListSerialization.data(
            fromPropertyList: ["settings.asrRule": "hanafi"],
            format: .binary,
            options: 0
        )
        let snapshot = BackupSnapshot(version: 99, createdAt: backupDate, keys: ["settings.asrRule"], payload: payload)
        store.values[BackupService.cloudKey] = try BackupService.encode(snapshot)

        let target = try makeDefaults()
        XCTAssertThrowsError(try BackupService(defaults: target, store: store).restore()) { error in
            XCTAssertEqual(error as? BackupError, .newerVersion)
        }
        XCTAssertNil(target.object(forKey: "settings.asrRule"))
    }

    func testRestoreIgnoresKeysOutsideTheList() throws {
        let store = TrustFakeStore()
        let payload = try PropertyListSerialization.data(
            fromPropertyList: ["settings.asrRule": "hanafi", "trust.firstName": "Someone", "other.key": 1] as [String: Any],
            format: .binary,
            options: 0
        )
        let snapshot = BackupSnapshot(
            version: 1,
            createdAt: backupDate,
            keys: ["other.key", "settings.asrRule", "trust.firstName"],
            payload: payload
        )
        store.values[BackupService.cloudKey] = try BackupService.encode(snapshot)

        let target = try makeDefaults()
        XCTAssertEqual(try BackupService(defaults: target, store: store).restore(), 1)
        XCTAssertEqual(target.string(forKey: "settings.asrRule"), "hanafi")
        XCTAssertNil(target.object(forKey: "trust.firstName"))
        XCTAssertNil(target.object(forKey: "other.key"))
    }

    func testRestoreOfGarbageThrowsUnreadable() throws {
        let store = TrustFakeStore()
        store.values[BackupService.cloudKey] = Data("not json".utf8)
        let service = BackupService(defaults: try makeDefaults(), store: store)
        XCTAssertNil(service.latestSnapshot())
        XCTAssertThrowsError(try service.restore()) { error in
            XCTAssertEqual(error as? BackupError, .unreadable)
        }
    }

    func testBackupWithUnavailableStoreThrowsWithoutCrashing() throws {
        let source = try makeDefaults()
        fillSource(source)
        let store = TrustFakeStore()
        store.dropsWrites = true
        XCTAssertThrowsError(try BackupService(defaults: source, store: store).backUp()) { error in
            XCTAssertEqual(error as? BackupError, .unavailable)
        }
    }

    func testIncludedKeyRules() {
        XCTAssertTrue(BackupService.isIncluded("prayedByDay"))
        XCTAssertTrue(BackupService.isIncluded("tracker.pauses"))
        XCTAssertTrue(BackupService.isIncluded("settings.alertMode.isha"))
        XCTAssertTrue(BackupService.isIncluded("tasbih.target"))
        XCTAssertTrue(BackupService.isIncluded("goals.anything"))
        XCTAssertFalse(BackupService.isIncluded("trust.firstName"))
        XCTAssertFalse(BackupService.isIncluded(WhatsNew.lastSeenKey))
        XCTAssertFalse(BackupService.isIncluded("translationSelectedID"))
        XCTAssertFalse(BackupService.isIncluded("placeName.cache"))
        XCTAssertFalse(BackupService.isIncluded("widgets.sharedPrayerConfig"))
    }

    // MARK: - What's new

    func testWhatsNewShouldShow() {
        XCTAssertTrue(WhatsNew.shouldShow(currentVersion: "0.1.0", lastSeen: nil))
        XCTAssertFalse(WhatsNew.shouldShow(currentVersion: "0.1.0", lastSeen: "0.1.0"))
        XCTAssertTrue(WhatsNew.shouldShow(currentVersion: "0.2.0", lastSeen: "0.1.0"))
        XCTAssertFalse(WhatsNew.shouldShow(currentVersion: nil, lastSeen: nil))
        XCTAssertFalse(WhatsNew.shouldShow(currentVersion: "", lastSeen: nil))
        XCTAssertFalse(WhatsNew.shouldShow(currentVersion: "  ", lastSeen: "0.1.0"))
    }

    func testWhatsNewShowsOncePerVersion() throws {
        let defaults = try makeDefaults()
        defaults.set(Data([1]), forKey: "prayedByDay")

        XCTAssertTrue(WhatsNew.evaluate(currentVersion: "0.1.0", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: WhatsNew.lastSeenKey), "0.1.0")
        XCTAssertFalse(WhatsNew.evaluate(currentVersion: "0.1.0", defaults: defaults))
        XCTAssertTrue(WhatsNew.evaluate(currentVersion: "0.2.0", defaults: defaults))
        XCTAssertFalse(WhatsNew.evaluate(currentVersion: "0.2.0", defaults: defaults))
    }

    func testWhatsNewSkipsAFreshInstallButRecordsIt() throws {
        let defaults = try makeDefaults()
        XCTAssertFalse(WhatsNew.evaluate(currentVersion: "0.1.0", defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: WhatsNew.lastSeenKey), "0.1.0")
        XCTAssertTrue(WhatsNew.evaluate(currentVersion: "0.2.0", defaults: defaults))
    }

    func testWhatsNewWaitsForTheFirstRunFlow() throws {
        let defaults = try makeDefaults()
        defaults.set(Data([1]), forKey: "prayedByDay")
        XCTAssertFalse(WhatsNew.evaluate(currentVersion: "0.1.0", defaults: defaults, firstRunFlowShows: true))
        XCTAssertEqual(defaults.string(forKey: WhatsNew.lastSeenKey), "0.1.0")
        XCTAssertFalse(WhatsNew.evaluate(currentVersion: "0.1.0", defaults: defaults))
    }

    func testWhatsNewListsRecentChanges() {
        XCTAssertEqual(WhatsNew.items.map(\.id), ["polish", "dayView", "tracker", "alerts", "goals"])
    }

    // MARK: - Feedback

    func testFeedbackBodyHasVersions() {
        let body = FeedbackMail.body(appVersion: "0.1.0", build: "2", systemVersion: "18.1")
        XCTAssertTrue(body.contains("App version 0.1.0 (2)"))
        XCTAssertTrue(body.contains("iOS 18.1"))
    }

    func testFeedbackMailtoLink() throws {
        let body = FeedbackMail.body(appVersion: "0.1.0", build: "2", systemVersion: "18.1")
        let url = try XCTUnwrap(FeedbackMail.mailtoURL(kind: .featureRequest, body: body))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:fiveskiesapp@gmail.com?"))
        XCTAssertTrue(url.absoluteString.contains("subject=Five%20Skies%20feature%20request"))
        XCTAssertTrue(url.absoluteString.contains("%0A"))
    }
}
