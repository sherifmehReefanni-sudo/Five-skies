import XCTest
@testable import FiveSkies

/// Pure logic of FiveSkies/Listen/UI/.
final class ListenUIModelTests: XCTestCase {
    private let a = Reciter(id: 1, name: "Reciter One", style: nil)
    private let b = Reciter(id: 2, name: "Reciter Two", style: "Murattal")

    func testSelectionPrefersSavedThenFirst() {
        XCTAssertEqual(ListenTabModel.resolveSelection(savedID: 2, in: [a, b]), b)
        XCTAssertEqual(ListenTabModel.resolveSelection(savedID: 9, in: [a, b]), a)
        XCTAssertEqual(ListenTabModel.resolveSelection(savedID: nil, in: [a, b]), a)
        XCTAssertNil(ListenTabModel.resolveSelection(savedID: 1, in: []))
    }

    @MainActor
    func testLoadRemembersChoice() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ListenUIModelTests"))
        defaults.removePersistentDomain(forName: "ListenUIModelTests")
        let model = ListenTabModel(catalog: FakeListenCatalog(), defaults: defaults)
        await model.loadAndWait()
        XCTAssertEqual(model.recitersState, .loaded)
        let second = model.reciters[1]
        model.select(second)
        XCTAssertEqual(defaults.object(forKey: ListenTabModel.reciterKey) as? Int, second.id)
        let again = ListenTabModel(catalog: FakeListenCatalog(), defaults: defaults)
        await again.loadAndWait()
        XCTAssertEqual(again.selectedReciter, second)
    }

    @MainActor
    func testLoadFailureShowsFailed() async {
        let model = ListenTabModel(catalog: FakeListenCatalog(failure: .notAvailable), defaults: UserDefaults(suiteName: "ListenUIModelTestsFail")!)
        await model.loadAndWait()
        XCTAssertEqual(model.recitersState, .failed)
        XCTAssertNil(model.selectedReciter)
    }

    func testClockFormat() {
        XCTAssertEqual(ListenTimeFormat.clock(0), "0:00")
        XCTAssertEqual(ListenTimeFormat.clock(65.9), "1:05")
        XCTAssertEqual(ListenTimeFormat.clock(3723), "1:02:03")
        XCTAssertEqual(ListenTimeFormat.clock(-4), "0:00")
        XCTAssertEqual(ListenTimeFormat.clock(.nan), "0:00")
        XCTAssertEqual(ListenTimeFormat.remaining(position: 30, duration: 95), "-1:05")
        XCTAssertEqual(ListenTimeFormat.spoken(61), "1 minute 1 second")
        XCTAssertEqual(ListenTimeFormat.spoken(0), "0 seconds")
    }

    func testSpeedLabels() {
        XCTAssertEqual(ListenSpeed.rates.map(ListenSpeed.label), ["0.75x", "1x", "1.25x", "1.5x", "2x"])
        XCTAssertEqual(ListenSpeed.spoken(1), "Normal speed")
        XCTAssertEqual(ListenSpeed.spoken(1.5), "1.5 times speed")
    }

    func testSleepCurrent() {
        let end = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(ListenSleepOption.current(chosen: .minutes(5), chosenChapter: nil, playingChapter: 1, timerEnd: end), .minutes(5))
        XCTAssertEqual(ListenSleepOption.current(chosen: .minutes(5), chosenChapter: nil, playingChapter: 1, timerEnd: nil), .off)
        XCTAssertEqual(ListenSleepOption.current(chosen: .endOfSurah, chosenChapter: 2, playingChapter: 2, timerEnd: nil), .endOfSurah)
        XCTAssertEqual(ListenSleepOption.current(chosen: .endOfSurah, chosenChapter: 2, playingChapter: 3, timerEnd: nil), .off)
        XCTAssertEqual(ListenSleepOption.all.count, 8)
    }
}
