import XCTest
@testable import FiveSkies

@MainActor
final class MemorizeTurnTests: XCTestCase {
    func testHidesOnlyDuringTheListenersTurnInThisSurah() {
        XCTAssertEqual(MemorizeTurn.hiddenAyah(readerChapter: 2, playingChapter: 2, hidesAyahWhileWaiting: true, isWaitingForListener: true, currentAyah: 5), 5)
        XCTAssertNil(MemorizeTurn.hiddenAyah(readerChapter: 2, playingChapter: 2, hidesAyahWhileWaiting: true, isWaitingForListener: false, currentAyah: 5))
        XCTAssertNil(MemorizeTurn.hiddenAyah(readerChapter: 2, playingChapter: 2, hidesAyahWhileWaiting: false, isWaitingForListener: true, currentAyah: 5))
        XCTAssertNil(MemorizeTurn.hiddenAyah(readerChapter: 3, playingChapter: 2, hidesAyahWhileWaiting: true, isWaitingForListener: true, currentAyah: 5))
        XCTAssertNil(MemorizeTurn.hiddenAyah(readerChapter: 2, playingChapter: nil, hidesAyahWhileWaiting: true, isWaitingForListener: true, currentAyah: 5))
    }

    func testFrozenTurnOnlyForItsChapter() {
        let arguments = ["app", MemorizeTurn.argument, "1:2"]
        XCTAssertEqual(MemorizeTurn.frozenAyah(forChapter: 1, arguments: arguments), 2)
        XCTAssertNil(MemorizeTurn.frozenAyah(forChapter: 2, arguments: arguments))
        XCTAssertNil(MemorizeTurn.frozenAyah(forChapter: 1, arguments: ["app"]))
        XCTAssertNil(MemorizeTurn.frozenAyah(forChapter: 1, arguments: ["app", MemorizeTurn.argument]))
    }

    func testKnownAyahsSurviveARelaunch() {
        let suite = "MemorizeTurnTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = KnownAyahsStore(defaults: defaults)
        store.markKnown(AyahRef(sura: 2, aya: 10))
        store.markKnown(AyahRef(sura: 2, aya: 9))
        store.markKnown(AyahRef(sura: 1, aya: 1))
        store.markKnown(AyahRef(sura: 2, aya: 9))
        XCTAssertEqual(store.count(inSura: 2), 2)

        let again = KnownAyahsStore(defaults: defaults)
        XCTAssertTrue(again.contains(AyahRef(sura: 2, aya: 10)))
        XCTAssertEqual(defaults.stringArray(forKey: KnownAyahsStore.key), ["1:1", "2:9", "2:10"])

        again.forget(AyahRef(sura: 2, aya: 10))
        XCTAssertFalse(KnownAyahsStore(defaults: defaults).contains(AyahRef(sura: 2, aya: 10)))
    }

    func testBadSavedKeysAreIgnored() {
        XCTAssertNil(KnownAyahsStore.ref(from: "2"))
        XCTAssertNil(KnownAyahsStore.ref(from: "0:1"))
        XCTAssertNil(KnownAyahsStore.ref(from: "a:b"))
        XCTAssertEqual(KnownAyahsStore.ref(from: "114:6"), AyahRef(sura: 114, aya: 6))
    }
}
