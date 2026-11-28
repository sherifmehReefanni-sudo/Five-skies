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

    func testBadTurnKeysAreIgnored() {
        XCTAssertNil(MemorizeTurn.ref(from: "2"))
        XCTAssertNil(MemorizeTurn.ref(from: "0:1"))
        XCTAssertNil(MemorizeTurn.ref(from: "a:b"))
        XCTAssertEqual(MemorizeTurn.ref(from: "114:6"), AyahRef(sura: 114, aya: 6))
    }
}
