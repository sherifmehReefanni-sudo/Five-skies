import XCTest
@testable import FiveSkies

final class ContinueCardTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUpWithError() throws {
        suiteName = "ContinueCardTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Store

    func testStartsEmpty() {
        let store = ContinueStore(defaults: defaults)
        XCTAssertNil(store.stored)
        XCTAssertNil(store.entry(now: start))
    }

    func testNewestWinsAcrossKinds() {
        let store = ContinueStore(defaults: defaults)
        store.noteReading(sura: 2, ayah: 45, at: start)
        XCTAssertEqual(store.entry(now: start)?.kind, .reading)

        store.noteListening(sura: 18, ayah: nil, reciterName: "Mishary Alafasy", at: start.addingTimeInterval(600))
        let listening = store.entry(now: start.addingTimeInterval(600))
        XCTAssertEqual(listening?.kind, .listening)
        XCTAssertEqual(listening?.sura, 18)
        XCTAssertNil(listening?.ayah)
        XCTAssertEqual(listening?.reciterName, "Mishary Alafasy")

        store.noteReading(sura: 36, ayah: 12, at: start.addingTimeInterval(1200))
        let reading = store.entry(now: start.addingTimeInterval(1200))
        XCTAssertEqual(reading?.kind, .reading)
        XCTAssertEqual(reading?.sura, 36)
        XCTAssertEqual(reading?.ayah, 12)
        XCTAssertNil(reading?.reciterName)
    }

    func testOlderNoteDoesNotReplaceNewer() {
        let store = ContinueStore(defaults: defaults)
        store.noteListening(sura: 1, ayah: 3, reciterName: "Reciter", at: start.addingTimeInterval(600))
        store.noteReading(sura: 2, ayah: 45, at: start)
        XCTAssertEqual(store.stored?.kind, .listening)
        XCTAssertEqual(store.stored?.sura, 1)
    }

    func testSameKindMovesForward() {
        let store = ContinueStore(defaults: defaults)
        store.noteReading(sura: 2, ayah: 45, at: start)
        store.noteReading(sura: 2, ayah: 46, at: start.addingTimeInterval(5))
        XCTAssertEqual(store.stored?.ayah, 46)
    }

    func testThirtyDayCutOff() {
        let store = ContinueStore(defaults: defaults)
        store.noteReading(sura: 2, ayah: 45, at: start)
        XCTAssertNotNil(store.entry(now: start.addingTimeInterval(29 * day)))
        XCTAssertNotNil(store.entry(now: start.addingTimeInterval(30 * day)))
        XCTAssertNil(store.entry(now: start.addingTimeInterval(30 * day + 1)))
        XCTAssertNil(store.entry(now: start.addingTimeInterval(45 * day)))
    }

    func testPersistence() {
        let first = ContinueStore(defaults: defaults)
        first.noteListening(sura: 67, ayah: 4, reciterName: "Reciter", at: start)

        let second = ContinueStore(defaults: defaults)
        XCTAssertEqual(
            second.stored,
            ContinueEntry(kind: .listening, sura: 67, ayah: 4, reciterName: "Reciter", date: start)
        )
        XCTAssertNotNil(defaults.data(forKey: ContinueStore.storageKey))
        XCTAssertEqual(ContinueStore.storageKey, "continue.last")
    }

    func testUnreadableStoredValueIsIgnored() {
        defaults.set(Data("not json".utf8), forKey: ContinueStore.storageKey)
        let store = ContinueStore(defaults: defaults)
        XCTAssertNil(store.stored)
        store.noteReading(sura: 2, ayah: 1, at: start)
        XCTAssertEqual(ContinueStore(defaults: defaults).stored?.sura, 2)
    }

    // MARK: - Label text

    func testReadingTitleAndSubtitle() {
        let entry = ContinueEntry(kind: .reading, sura: 2, ayah: 45, reciterName: nil, date: start)
        XCTAssertEqual(ContinueCardText.title(for: entry, suraName: "Al-Baqara"), "Continue: Al-Baqara, ayah 45")
        XCTAssertEqual(ContinueCardText.subtitle(for: entry), "Reading")
        XCTAssertEqual(ContinueCardText.symbol(for: .reading), "book.fill")
    }

    func testListeningTitleAndSubtitle() {
        let entry = ContinueEntry(kind: .listening, sura: 18, ayah: nil, reciterName: "Mishary Alafasy", date: start)
        XCTAssertEqual(ContinueCardText.title(for: entry, suraName: "Al-Kahf"), "Continue: Al-Kahf")
        XCTAssertEqual(ContinueCardText.subtitle(for: entry), "Listening \u{00B7} Mishary Alafasy")
        XCTAssertEqual(ContinueCardText.symbol(for: .listening), "headphones")

        let noName = ContinueEntry(kind: .listening, sura: 18, ayah: 10, reciterName: "  ", date: start)
        XCTAssertEqual(ContinueCardText.subtitle(for: noName), "Listening")
        XCTAssertEqual(ContinueCardText.title(for: noName, suraName: "Al-Kahf"), "Continue: Al-Kahf, ayah 10")
    }

    func testTitleFallsBackWhileQuranLoads() {
        let entry = ContinueEntry(kind: .reading, sura: 2, ayah: 45, reciterName: nil, date: start)
        XCTAssertEqual(ContinueCardText.title(for: entry, suraName: nil), "Continue: Surah 2, ayah 45")
    }

    // MARK: - Screenshot mode

    func testFixedPhaseHidesUnlessSampleRequested() {
        let stored = ContinueEntry(kind: .listening, sura: 1, ayah: nil, reciterName: "Reciter", date: start)

        let normal = ContinueCardMode(isFixedPhase: false, wantsSample: false)
        XCTAssertEqual(normal.displayedEntry(stored: stored, now: start), stored)
        XCTAssertNil(normal.displayedEntry(stored: nil, now: start))
        XCTAssertNil(normal.displayedEntry(stored: stored, now: start.addingTimeInterval(31 * day)))

        let fixed = ContinueCardMode(isFixedPhase: true, wantsSample: false)
        XCTAssertNil(fixed.displayedEntry(stored: stored, now: start))

        let sample = ContinueCardMode(isFixedPhase: true, wantsSample: true)
        XCTAssertEqual(
            sample.displayedEntry(stored: stored, now: start),
            ContinueEntry(kind: .reading, sura: 2, ayah: 45, reciterName: nil, date: start)
        )

        // The sample flag alone does nothing outside screenshot mode.
        let sampleOnly = ContinueCardMode(isFixedPhase: false, wantsSample: true)
        XCTAssertEqual(sampleOnly.displayedEntry(stored: stored, now: start), stored)
    }
}
