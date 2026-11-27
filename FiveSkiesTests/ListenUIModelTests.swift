import XCTest
@testable import FiveSkies

/// Pure logic of FiveSkies/Listen/UI/.
final class ListenUIModelTests: XCTestCase {
    private let a = Reciter(id: 1, name: "Reciter One", style: nil)
    private let b = Reciter(id: 2, name: "Reciter Two", style: "Murattal")

    func testSelectionPrefersSavedThenFirst() {
        XCTAssertEqual(QuranListenModel.resolveSelection(savedID: 2, in: [a, b]), b)
        XCTAssertEqual(QuranListenModel.resolveSelection(savedID: 9, in: [a, b]), a)
        XCTAssertEqual(QuranListenModel.resolveSelection(savedID: nil, in: [a, b]), a)
        XCTAssertNil(QuranListenModel.resolveSelection(savedID: 1, in: []))
    }

    @MainActor
    func testLoadRemembersChoice() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ListenUIModelTests"))
        defaults.removePersistentDomain(forName: "ListenUIModelTests")
        let model = QuranListenModel(catalog: FakeListenCatalog(), defaults: defaults)
        await model.loadAndWait()
        XCTAssertEqual(model.recitersState, .loaded)
        let second = model.reciters[1]
        model.select(second)
        XCTAssertEqual(defaults.object(forKey: QuranListenModel.reciterKey) as? Int, second.id)
        let again = QuranListenModel(catalog: FakeListenCatalog(), defaults: defaults)
        await again.loadAndWait()
        XCTAssertEqual(again.selectedReciter, second)
    }

    @MainActor
    func testLoadFailureShowsFailed() async {
        let model = QuranListenModel(catalog: FakeListenCatalog(failure: .notAvailable), defaults: UserDefaults(suiteName: "ListenUIModelTestsFail")!)
        await model.loadAndWait()
        XCTAssertEqual(model.recitersState, .failed)
        XCTAssertNil(model.selectedReciter)
        XCTAssertEqual(model.failureMessage, ListenCatalogError.notAvailable.userMessage)
        XCTAssertFalse(model.offersPlayback)
    }

    @MainActor
    func testOffersPlaybackWhileLoadingAndWithAReciter() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ListenUIModelTestsOffers"))
        defaults.removePersistentDomain(forName: "ListenUIModelTestsOffers")
        let model = QuranListenModel(catalog: FakeListenCatalog(), defaults: defaults)
        XCTAssertTrue(model.offersPlayback)
        await model.loadAndWait()
        XCTAssertNotNil(model.selectedReciter)
        XCTAssertTrue(model.offersPlayback)
    }

    func testQueueResolverUsesBundledNamesAndCatalog() async throws {
        let suras = [
            Sura(number: 1, arabicName: "", transliteratedName: "First Name", englishName: "One",
                 revelation: .meccan, ayahCount: 7, firstAyahIndex: 0),
            Sura(number: 2, arabicName: "", transliteratedName: "Second Name", englishName: "Two",
                 revelation: .medinan, ayahCount: 286, firstAyahIndex: 7),
        ]
        let resolver = ListenCatalogQueueResolver(catalog: FakeListenCatalog(), suras: suras)
        let item = try await resolver.item(chapter: 2, reciter: b)
        XCTAssertEqual(item.chapter, 2)
        XCTAssertEqual(item.chapterName, "Second Name")
        XCTAssertEqual(item.reciter, b)
        XCTAssertEqual(item.audio.url, FakeListenCatalog.sampleURL(reciterID: 2, chapter: 2))
        let unnamed = try await resolver.item(chapter: 3, reciter: b)
        XCTAssertEqual(unnamed.chapterName, "Surah 3")
        do {
            _ = try await resolver.item(chapter: 115, reciter: b)
            XCTFail("Surah 115 should not resolve")
        } catch {
            XCTAssertEqual(error as? ListenCatalogError, .notFound)
        }
    }

    func testPlayModeWords() {
        XCTAssertEqual(ListenPlayModeText.surahEnd(.stop), "Stop")
        XCTAssertEqual(ListenPlayModeText.surahEnd(.playNext), "Play the next surah")
        XCTAssertEqual(ListenPlayModeText.surahEnd(.repeatSurah(times: 1)), "Repeat 1 time")
        XCTAssertEqual(ListenPlayModeText.surahEnd(.repeatSurah(times: 7)), "Repeat 7 times")
        XCTAssertEqual(ListenPlayModeText.surahEnd(.repeatSurah(times: nil)), "Repeat until stopped")
        XCTAssertEqual(ListenPlayModeText.surahEnd(.playSet(first: 2, last: 5)), "Surahs 2 to 5")
        XCTAssertEqual(PlayModes.ayahRepeatChoices.map(ListenPlayModeText.ayahRepeat), ["Off", "2 times", "3 times", "5 times", "10 times"])
        XCTAssertEqual(ListenPlayModeText.prayerPause("Asr"), "Paused for Asr. Resume?")
        XCTAssertEqual(ListenCreditLine.text(for: b), "Reciter Two \u{00B7} Quran Foundation")
    }

    func testSetRangeStaysInOrderAndInRange() {
        XCTAssertEqual(ListenSetRange.starting(at: 36), .playSet(first: 36, last: 114))
        XCTAssertEqual(ListenSetRange.starting(at: 0), .playSet(first: 1, last: 114))
        XCTAssertEqual(ListenSetRange.changingFirst(10, last: 5), .playSet(first: 10, last: 10))
        XCTAssertEqual(ListenSetRange.changingFirst(3, last: 5), .playSet(first: 3, last: 5))
        XCTAssertEqual(ListenSetRange.changingLast(2, first: 5), .playSet(first: 2, last: 2))
        XCTAssertEqual(ListenSetRange.changingLast(200, first: 5), .playSet(first: 5, last: 114))
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
