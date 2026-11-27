import XCTest
@testable import FiveSkies

// Round C1 play modes on ListenPlayer, with the silent SimulatedEngine.
// All timings are made-up numbers. No religious text.

private let testReciter = Reciter(id: 7, name: "Test Reciter", style: nil)

private func makeItem(chapter: Int, reciter: Reciter = testReciter, duration: Double? = 300) -> NowPlayingItem {
    let audio = ChapterAudio(
        reciterID: reciter.id,
        chapter: chapter,
        url: URL(string: "https://example.com/audio/\(reciter.id)/\(chapter).mp3")!,
        durationSeconds: duration
    )
    return NowPlayingItem(reciter: reciter, chapter: chapter, chapterName: "Chapter \(chapter)", audio: audio)
}

/// Nine ayahs over 300 seconds: 0-12, 12-40, 40-70, 70-100, 100-150, 150-200, 200-240, 240-270, 270-300.
/// Each ayah has three words of equal length, positions 1 to 3.
private let standardBounds: [Double] = [0, 12, 40, 70, 100, 150, 200, 240, 270, 300]

private func makeTimings(chapter: Int, reciterID: Int = 7, bounds: [Double] = standardBounds) -> SurahTimings {
    var ayahs: [AyahTiming] = []
    for index in 1..<bounds.count {
        let start = bounds[index - 1]
        let end = bounds[index]
        let step = (end - start) / 3
        let words = (0..<3).map { word in
            WordTiming(position: word + 1, start: start + step * Double(word), end: start + step * Double(word + 1))
        }
        ayahs.append(AyahTiming(ayah: index, start: start, end: end, words: words))
    }
    return SurahTimings(reciterID: reciterID, chapter: chapter, ayahs: ayahs)
}

private struct FakeTimingProvider: SurahTimingProviding {
    let byChapter: [Int: SurahTimings]

    func timings(reciterID: Int, chapter: Int) async -> SurahTimings? {
        byChapter[chapter]
    }
}

private struct FakeQueueError: Error {}

private final class FakeQueue: ListenQueueResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Int] = []
    private var failing: Set<Int> = []

    var requested: [Int] {
        lock.withLock { asked }
    }

    func setFailing(_ chapters: Set<Int>) {
        lock.withLock { failing = chapters }
    }

    func item(chapter: Int, reciter: Reciter) async throws -> NowPlayingItem {
        let fails = lock.withLock { () -> Bool in
            asked.append(chapter)
            return failing.contains(chapter)
        }
        if fails { throw FakeQueueError() }
        return makeItem(chapter: chapter, reciter: reciter)
    }
}

/// Records recite after me waits so a test can end them by hand.
private final class WaitRecorder {
    private(set) var seconds: [Double] = []
    private var actions: [@MainActor @Sendable () -> Void] = []

    func record(_ seconds: Double, _ action: @escaping @MainActor @Sendable () -> Void) {
        self.seconds.append(seconds)
        actions.append(action)
    }

    @MainActor
    func finishLast() {
        actions.last?()
    }
}

final class ListenPlayModesTests: XCTestCase {
    private static let suiteName = "ListenPlayModesTests"

    private struct Harness {
        let player: ListenPlayer
        let engine: SimulatedEngine
        let defaults: UserDefaults
        let waits: WaitRecorder
    }

    @MainActor
    private func makeHarness(
        timings: [Int: SurahTimings]? = nil,
        queue: FakeQueue? = nil,
        clearing: Bool = true
    ) -> Harness {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        if clearing {
            defaults.removePersistentDomain(forName: Self.suiteName)
        }
        let engine = SimulatedEngine(defaultDuration: 300)
        let player = ListenPlayer(engine: engine, system: QuietListenSystem(), defaults: defaults)
        let waits = WaitRecorder()
        player.scheduleWait = { seconds, action in
            waits.record(seconds, action)
        }
        if let timings {
            player.timingProvider = FakeTimingProvider(byChapter: timings)
        }
        player.queueResolver = queue
        return Harness(player: player, engine: engine, defaults: defaults, waits: waits)
    }

    // MARK: - Modes persistence

    @MainActor
    func testModesAreSavedAndReadBack() {
        let h = makeHarness()
        XCTAssertEqual(h.player.modes, PlayModes())

        var chosen = PlayModes()
        chosen.surahEnd = .playSet(first: 78, last: 114)
        chosen.ayahRepeat = 5
        chosen.reciteAfterMe = true
        chosen.pausesForPrayer = false
        h.player.modes = chosen
        XCTAssertNotNil(h.defaults.data(forKey: ListenPlayer.modesKey))
        XCTAssertEqual(ListenPlayer(engine: SimulatedEngine(), defaults: h.defaults).modes, chosen)

        h.player.modes.surahEnd = .repeatSurah(times: nil)
        XCTAssertEqual(ListenPlayer(engine: SimulatedEngine(), defaults: h.defaults).modes.surahEnd, .repeatSurah(times: nil))
        h.player.modes.surahEnd = .repeatSurah(times: 3)
        XCTAssertEqual(ListenPlayer(engine: SimulatedEngine(), defaults: h.defaults).modes.surahEnd, .repeatSurah(times: 3))

        h.defaults.set(Data("not json".utf8), forKey: ListenPlayer.modesKey)
        XCTAssertEqual(ListenPlayer(engine: SimulatedEngine(), defaults: h.defaults).modes, PlayModes())
    }

    // MARK: - When the surah ends

    @MainActor
    func testStopEndsPausedAtTheStart() {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.item?.chapter, 1)
        XCTAssertEqual(queue.requested, [])
    }

    @MainActor
    func testPlayNextMovesToTheFollowingSurah() async {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .loading)

        await h.player.queueLookupFinished()
        XCTAssertEqual(queue.requested, [2])
        XCTAssertEqual(h.player.item, makeItem(chapter: 2))
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.engine.loadCount, 2)
        XCTAssertTrue(h.engine.isPlaying)
    }

    @MainActor
    func testPlayNextStopsAfterTheLastSurah() {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 114))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.item?.chapter, 114)
        XCTAssertEqual(queue.requested, [])
    }

    @MainActor
    func testPlayNextWithoutAResolverStops() {
        let h = makeHarness()
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.item?.chapter, 1)
    }

    @MainActor
    func testNextSurahFailureShowsTheFriendlyMessageAndRetries() async {
        let queue = FakeQueue()
        queue.setFailing([2])
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        await h.player.queueLookupFinished()
        XCTAssertEqual(h.player.state, .failed(ListenPlayer.failureMessage))
        XCTAssertEqual(h.player.item?.chapter, 1)

        queue.setFailing([])
        h.player.resume()
        await h.player.queueLookupFinished()
        XCTAssertEqual(queue.requested, [2, 2])
        XCTAssertEqual(h.player.item?.chapter, 2)
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testRepeatSurahCountsRepeatsAfterTheFirstPlay() {
        let h = makeHarness()
        h.player.modes.surahEnd = .repeatSurah(times: 2)
        h.player.play(makeItem(chapter: 1))

        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.surahRepeatsDone, 1)

        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.surahRepeatsDone, 2)

        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.surahRepeatsDone, 0)
        XCTAssertEqual(h.engine.loadCount, 1)
    }

    @MainActor
    func testRepeatSurahCountStartsAgainForANewSurah() {
        let h = makeHarness()
        h.player.modes.surahEnd = .repeatSurah(times: 3)
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.surahRepeatsDone, 1)
        h.player.play(makeItem(chapter: 2))
        XCTAssertEqual(h.player.surahRepeatsDone, 0)
    }

    @MainActor
    func testRepeatUntilStoppedKeepsGoing() {
        let h = makeHarness()
        h.player.modes.surahEnd = .repeatSurah(times: nil)
        h.player.play(makeItem(chapter: 1))
        for _ in 0..<6 {
            h.engine.tick(by: 300)
        }
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.surahRepeatsDone, 6)
        XCTAssertTrue(h.engine.isPlaying)
    }

    @MainActor
    func testPlaySetMovesThroughTheSetThenStops() async {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playSet(first: 2, last: 3)
        h.player.play(makeItem(chapter: 2))
        h.engine.tick(by: 300)
        await h.player.queueLookupFinished()
        XCTAssertEqual(h.player.item?.chapter, 3)
        XCTAssertEqual(h.player.state, .playing)

        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.item?.chapter, 3)
        XCTAssertEqual(queue.requested, [3])
    }

    @MainActor
    func testPlaySetFromOutsideTheSetGoesToItsFirstSurah() async {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playSet(first: 5, last: 6)
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        await h.player.queueLookupFinished()
        XCTAssertEqual(queue.requested, [5])
        XCTAssertEqual(h.player.item?.chapter, 5)

        h.player.play(makeItem(chapter: 9))
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(queue.requested, [5])
    }

    // MARK: - Sleep at end of surah wins

    @MainActor
    func testSleepAtEndOfSurahWinsOverPlayNext() {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        h.player.sleepAtEndOfSurah()
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertFalse(h.player.sleepsAtEndOfSurah)
        XCTAssertEqual(queue.requested, [])
    }

    @MainActor
    func testSleepAtEndOfSurahWinsOverRepeatAndPlaySet() {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.modes.surahEnd = .repeatSurah(times: nil)
        h.player.play(makeItem(chapter: 1))
        h.player.sleepAtEndOfSurah()
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)

        h.player.modes.surahEnd = .playSet(first: 1, last: 10)
        h.player.resume()
        h.player.sleepAtEndOfSurah()
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(queue.requested, [])
    }

    @MainActor
    func testSleepAtEndOfSurahWaitsForTheLastAyahRepeats() async {
        let queue = FakeQueue()
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)], queue: queue)
        h.player.modes.surahEnd = .playNext
        h.player.modes.ayahRepeat = 2
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.player.sleepAtEndOfSurah()
        h.player.seek(to: 280)

        h.engine.tick(by: 20)
        XCTAssertEqual(h.player.position, 270, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)

        h.engine.tick(by: 30)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(queue.requested, [])
    }

    // MARK: - Timings and lookup

    func testAyahLookupUsesStartsAndEnds() {
        let ayahs = [
            AyahTiming(ayah: 1, start: 2, end: 10, words: []),
            AyahTiming(ayah: 2, start: 12, end: 20, words: []),
            AyahTiming(ayah: 3, start: 20, end: 30, words: [])
        ]
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 0, in: ayahs))
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 2, in: ayahs), 0)
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 9.99, in: ayahs), 0)
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 10, in: ayahs))
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 11, in: ayahs))
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 12, in: ayahs), 1)
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 20, in: ayahs), 2)
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 29.9, in: ayahs), 2)
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 30, in: ayahs))
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 500, in: ayahs))
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: .nan, in: ayahs))
        XCTAssertNil(ListenTimingLookup.ayahIndex(at: 5, in: []))

        let many = (0..<1_000).map { AyahTiming(ayah: $0 + 1, start: Double($0), end: Double($0) + 1, words: []) }
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 567.5, in: many), 567)
        XCTAssertEqual(ListenTimingLookup.ayahIndex(at: 999.9, in: many), 999)
    }

    func testWordLookupGivesTheWordPosition() {
        let words = [
            WordTiming(position: 1, start: 2, end: 4),
            WordTiming(position: 2, start: 4.5, end: 7),
            WordTiming(position: 3, start: 7, end: 10)
        ]
        XCTAssertNil(ListenTimingLookup.wordPosition(at: 1, in: words))
        XCTAssertEqual(ListenTimingLookup.wordPosition(at: 3, in: words), 1)
        XCTAssertNil(ListenTimingLookup.wordPosition(at: 4.2, in: words))
        XCTAssertEqual(ListenTimingLookup.wordPosition(at: 5, in: words), 2)
        XCTAssertEqual(ListenTimingLookup.wordPosition(at: 7, in: words), 3)
        XCTAssertNil(ListenTimingLookup.wordPosition(at: 10, in: words))
        XCTAssertNil(ListenTimingLookup.wordPosition(at: 3, in: []))
    }

    func testPreparedTimingsAreCheckedAndSorted() {
        let messy = SurahTimings(reciterID: 7, chapter: 1, ayahs: [
            AyahTiming(ayah: 2, start: 10, end: 20, words: [
                WordTiming(position: 2, start: 15, end: 20),
                WordTiming(position: 1, start: 10, end: 15),
                WordTiming(position: 3, start: 18, end: 18)
            ]),
            AyahTiming(ayah: 1, start: 0, end: 10, words: []),
            AyahTiming(ayah: 3, start: 30, end: 25, words: []),
            AyahTiming(ayah: 4, start: .nan, end: 40, words: [])
        ])
        let prepared = ListenTimingLookup.prepared(messy, reciterID: 7, chapter: 1)
        XCTAssertEqual(prepared?.ayahs.map(\.ayah), [1, 2])
        XCTAssertEqual(prepared?.ayahs.last?.words.map(\.position), [1, 2])

        XCTAssertNil(ListenTimingLookup.prepared(messy, reciterID: 8, chapter: 1))
        XCTAssertNil(ListenTimingLookup.prepared(messy, reciterID: 7, chapter: 2))
        let empty = SurahTimings(reciterID: 7, chapter: 1, ayahs: [])
        XCTAssertNil(ListenTimingLookup.prepared(empty, reciterID: 7, chapter: 1))
    }

    @MainActor
    func testTimingsPublishCurrentAyahAndWord() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.play(makeItem(chapter: 1))
        XCTAssertFalse(h.player.timingsAvailable)
        XCTAssertNil(h.player.currentAyah)

        await h.player.timingsLoadFinished()
        XCTAssertTrue(h.player.timingsAvailable)
        XCTAssertEqual(h.player.timings?.ayahs.count, 9)
        XCTAssertEqual(h.player.currentAyah, 1)
        XCTAssertEqual(h.player.currentWord, 1)

        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.currentAyah, 1)
        XCTAssertEqual(h.player.currentWord, 2)

        h.engine.tick(by: 10)
        XCTAssertEqual(h.player.currentAyah, 2)
        XCTAssertEqual(h.player.currentWord, 1)

        h.player.seek(to: 101)
        XCTAssertEqual(h.player.currentAyah, 5)
        XCTAssertEqual(h.player.currentWord, 1)
        h.player.seek(to: 149)
        XCTAssertEqual(h.player.currentWord, 3)

        h.player.play(makeItem(chapter: 2))
        XCTAssertNil(h.player.timings)
        XCTAssertNil(h.player.currentAyah)
        XCTAssertNil(h.player.currentWord)
        XCTAssertFalse(h.player.timingsAvailable)
    }

    @MainActor
    func testTimingsForAnotherReciterAreNotUsed() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1, reciterID: 99)])
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        XCTAssertFalse(h.player.timingsAvailable)
        XCTAssertNil(h.player.timings)
    }

    @MainActor
    func testWithoutTimingsTheAyahOptionsDoNothing() async {
        let h = makeHarness(timings: [:])
        h.player.modes.ayahRepeat = 3
        h.player.modes.reciteAfterMe = true
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        XCTAssertFalse(h.player.timingsAvailable)

        h.engine.tick(by: 30)
        XCTAssertEqual(h.player.position, 30, accuracy: 0.001)
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [])
        XCTAssertNil(h.player.currentAyah)

        XCTAssertFalse(h.player.setLoopAyahs(1...2))
        XCTAssertNil(h.player.loopRange)

        h.player.play(makeItem(chapter: 1), fromAyah: 3)
        XCTAssertEqual(h.player.position, 30, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)
    }

    // MARK: - Ayah repeat

    @MainActor
    func testAyahRepeatPlaysEachAyahTheChosenNumberOfTimes() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.ayahRepeat = 3
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()

        h.engine.tick(by: 6)
        h.engine.tick(by: 6)
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)
        XCTAssertEqual(h.engine.position, 0, accuracy: 0.001)
        XCTAssertEqual(h.player.currentAyah, 1)

        h.engine.tick(by: 12)
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)

        h.engine.tick(by: 12)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)
        XCTAssertEqual(h.player.currentAyah, 2)

        h.engine.tick(by: 28)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testAyahRepeatOnTheLastAyahThenTheSurahEnds() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.ayahRepeat = 2
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.player.seek(to: 280)

        h.engine.tick(by: 20)
        XCTAssertEqual(h.player.position, 270, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)

        h.engine.tick(by: 30)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
    }

    @MainActor
    func testSeekingStartsTheAyahCountAgain() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.ayahRepeat = 2
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.engine.tick(by: 12)
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)

        h.player.seek(to: 5)
        h.engine.tick(by: 7)
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)
    }

    // MARK: - Recite after me

    @MainActor
    func testReciteAfterMeWaitsAsLongAsTheAyah() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.reciteAfterMe = true
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()

        h.engine.tick(by: 12)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertFalse(h.engine.isPlaying)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.waits.seconds, [12])
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)

        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)

        h.waits.finishLast()
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertTrue(h.engine.isPlaying)

        h.engine.tick(by: 28)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [12, 28])

        h.player.continueAfterListener()
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertTrue(h.engine.isPlaying)
        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.position, 45, accuracy: 0.001)
    }

    @MainActor
    func testReciteAfterMeWithAyahRepeatWaitsAfterEveryPlay() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.reciteAfterMe = true
        h.player.modes.ayahRepeat = 2
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()

        h.engine.tick(by: 12)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)
        h.waits.finishLast()

        h.engine.tick(by: 12)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)
        XCTAssertEqual(h.waits.seconds, [12, 12])
    }

    @MainActor
    func testPausingEndsTheListenersTurn() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.reciteAfterMe = true
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.engine.tick(by: 12)
        XCTAssertTrue(h.player.isWaitingForListener)

        h.player.pause()
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertEqual(h.player.state, .paused)

        // A late timer does nothing.
        h.waits.finishLast()
        XCTAssertFalse(h.engine.isPlaying)

        h.player.resume()
        XCTAssertTrue(h.engine.isPlaying)
        h.engine.tick(by: 3)
        XCTAssertEqual(h.player.position, 15, accuracy: 0.001)
    }

    @MainActor
    func testTurningReciteAfterMeOffEndsTheWait() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.reciteAfterMe = true
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.engine.tick(by: 12)
        h.player.modes.reciteAfterMe = false
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertTrue(h.engine.isPlaying)
    }

    @MainActor
    func testReciteAfterMeOnTheLastAyahThenPlaysNext() async {
        let queue = FakeQueue()
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)], queue: queue)
        h.player.modes.reciteAfterMe = true
        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.player.seek(to: 280)

        h.engine.tick(by: 20)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [30])
        XCTAssertEqual(queue.requested, [])

        h.waits.finishLast()
        await h.player.queueLookupFinished()
        XCTAssertEqual(queue.requested, [2])
        XCTAssertEqual(h.player.item?.chapter, 2)
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testPausingDuringTheLastTurnEndsTheSurah() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.modes.reciteAfterMe = true
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.player.seek(to: 280)
        h.engine.tick(by: 20)
        XCTAssertTrue(h.player.isWaitingForListener)

        h.player.pause()
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
    }

    // MARK: - Play from ayah and loop ayahs

    @MainActor
    func testPlayFromAyahWaitsForTimingsThenStartsThere() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1), 2: makeTimings(chapter: 2)])
        h.player.play(makeItem(chapter: 1), fromAyah: 4)
        XCTAssertEqual(h.player.state, .loading)
        XCTAssertFalse(h.engine.isPlaying)

        await h.player.timingsLoadFinished()
        XCTAssertEqual(h.player.position, 70, accuracy: 0.001)
        XCTAssertEqual(h.player.currentAyah, 4)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertTrue(h.engine.isPlaying)

        h.player.play(makeItem(chapter: 1), fromAyah: 6)
        XCTAssertEqual(h.player.position, 150, accuracy: 0.001)
        XCTAssertEqual(h.player.currentAyah, 6)
        XCTAssertEqual(h.engine.loadCount, 1)

        h.player.play(makeItem(chapter: 2), fromAyah: 50)
        await h.player.timingsLoadFinished()
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testPlayFromAyahWithoutATimingProviderStartsAtTheBeginning() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1), fromAyah: 4)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 0)
    }

    @MainActor
    func testLoopAyahsUsesTheTimeLoop() async {
        let h = makeHarness(timings: [1: makeTimings(chapter: 1)])
        h.player.play(makeItem(chapter: 1))
        await h.player.timingsLoadFinished()

        XCTAssertTrue(h.player.setLoopAyahs(2...3))
        XCTAssertEqual(h.player.loopRange, 12.0...70.0)
        XCTAssertEqual(h.player.loopAyahs, 2...3)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)

        h.engine.tick(by: 30)
        h.engine.tick(by: 30)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)
        XCTAssertEqual(h.player.currentAyah, 2)

        XCTAssertFalse(h.player.setLoopAyahs(2...40))
        XCTAssertEqual(h.player.loopAyahs, 2...3)

        h.player.setLoopRange(100.0...120.0)
        XCTAssertNil(h.player.loopAyahs)

        XCTAssertTrue(h.player.setLoopAyahs(1...1))
        XCTAssertEqual(h.player.loopRange, 0.0...12.0)
        XCTAssertTrue(h.player.setLoopAyahs(nil))
        XCTAssertNil(h.player.loopRange)
        XCTAssertNil(h.player.loopAyahs)

        h.player.setLoopAyahs(4...5)
        h.player.play(makeItem(chapter: 2))
        XCTAssertNil(h.player.loopAyahs)
        XCTAssertNil(h.player.loopRange)
    }

    // MARK: - Pause for prayer

    @MainActor
    func testPauseForPrayerPausesAndClearsOnResume() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.player.prayerTimeArrived(name: "Asr")
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.pausedForPrayer, "Asr")
        XCTAssertFalse(h.engine.isPlaying)

        h.player.resume()
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertNil(h.player.pausedForPrayer)

        h.player.prayerTimeArrived(name: "Maghrib")
        XCTAssertEqual(h.player.pausedForPrayer, "Maghrib")
        h.player.stop()
        XCTAssertNil(h.player.pausedForPrayer)
    }

    @MainActor
    func testPauseForPrayerOffOrNotPlayingDoesNothing() {
        let h = makeHarness()
        h.player.modes.pausesForPrayer = false
        h.player.play(makeItem(chapter: 1))
        h.player.prayerTimeArrived(name: "Isha")
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertNil(h.player.pausedForPrayer)

        h.player.modes.pausesForPrayer = true
        h.player.pause()
        h.player.prayerTimeArrived(name: "Isha")
        XCTAssertNil(h.player.pausedForPrayer)

        h.player.stop()
        h.player.prayerTimeArrived(name: "Isha")
        XCTAssertNil(h.player.pausedForPrayer)
        XCTAssertEqual(h.player.state, .idle)
    }

    // MARK: - Resume where I stopped

    @MainActor
    func testResumeSpotIsSavedAndUsedNextTime() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 100)
        h.player.pause()
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 1), 100)
        h.player.stop()

        let again = makeHarness(clearing: false)
        again.player.play(makeItem(chapter: 1))
        XCTAssertEqual(again.player.position, 100, accuracy: 0.001)
        XCTAssertEqual(again.engine.position, 100, accuracy: 0.001)
        XCTAssertEqual(again.player.resumedFrom, 100)
        XCTAssertEqual(again.player.state, .playing)

        again.player.startOver()
        XCTAssertEqual(again.player.position, 0)
        XCTAssertNil(again.player.resumedFrom)
        XCTAssertNil(again.player.savedPosition(reciterID: 7, chapter: 1))
    }

    @MainActor
    func testResumeSpotIsSavedWhilePlaying() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 6)
        h.engine.tick(by: 20)
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 1), 26)
    }

    @MainActor
    func testResumeSpotsNearEitherEndAreNotKept() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 100)
        h.player.pause()
        XCTAssertNotNil(h.player.savedPosition(reciterID: 7, chapter: 1))

        h.player.seek(to: 5)
        h.player.pause()
        XCTAssertNil(h.player.savedPosition(reciterID: 7, chapter: 1))

        h.player.seek(to: 295)
        h.player.pause()
        XCTAssertNil(h.player.savedPosition(reciterID: 7, chapter: 1))

        XCTAssertFalse(ListenPlayer.isResumable(10, duration: 300))
        XCTAssertTrue(ListenPlayer.isResumable(10.5, duration: 300))
        XCTAssertFalse(ListenPlayer.isResumable(290, duration: 300))
        XCTAssertTrue(ListenPlayer.isResumable(289, duration: 300))
        XCTAssertTrue(ListenPlayer.isResumable(500, duration: 0))
    }

    @MainActor
    func testResumeSpotIsPerReciterAndSurah() {
        let other = Reciter(id: 8, name: "Other Reciter", style: nil)
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 50)
        h.player.play(makeItem(chapter: 1, reciter: other))
        h.engine.tick(by: 80)
        h.player.stop()
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 1), 50)
        XCTAssertEqual(h.player.savedPosition(reciterID: 8, chapter: 1), 80)
        XCTAssertNil(h.player.savedPosition(reciterID: 7, chapter: 2))
    }

    @MainActor
    func testResumeKeepsTheNewestFifty() throws {
        let h = makeHarness()
        for chapter in 1...55 {
            h.player.play(makeItem(chapter: chapter))
            h.engine.tick(by: 20)
        }
        h.player.stop()
        let data = try XCTUnwrap(h.defaults.data(forKey: ListenPlayer.resumeKey))
        let entries = try JSONDecoder().decode([ListenResumeEntry].self, from: data)
        XCTAssertEqual(entries.count, 50)
        XCTAssertNil(h.player.savedPosition(reciterID: 7, chapter: 5))
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 6), 20)
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 55), 20)
    }

    @MainActor
    func testFinishingASurahForgetsItsSpot() {
        let h = makeHarness()
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 100)
        h.player.pause()
        h.player.resume()
        h.engine.tick(by: 200)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertNil(h.player.savedPosition(reciterID: 7, chapter: 1))
    }

    @MainActor
    func testTheNextSurahInTheQueueStartsAtTheBeginning() async {
        let queue = FakeQueue()
        let h = makeHarness(queue: queue)
        h.player.play(makeItem(chapter: 2))
        h.engine.tick(by: 100)
        h.player.pause()
        XCTAssertEqual(h.player.savedPosition(reciterID: 7, chapter: 2), 100)

        h.player.modes.surahEnd = .playNext
        h.player.play(makeItem(chapter: 1))
        h.engine.tick(by: 300)
        await h.player.queueLookupFinished()
        XCTAssertEqual(h.player.item?.chapter, 2)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertNil(h.player.resumedFrom)
    }
}
