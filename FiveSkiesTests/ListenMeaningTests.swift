import XCTest
@testable import FiveSkies

// Read the meaning after each ayah, with the silent SimulatedEngine and SimulatedMeaningSpeaker.
// Timings are made-up numbers and meanings are placeholder English. No religious text.
// Arabic script is only ever built from code points at run time.

private let meaningReciter = Reciter(id: 7, name: "Test Reciter", style: nil)

private func meaningItem(chapter: Int) -> NowPlayingItem {
    let audio = ChapterAudio(
        reciterID: meaningReciter.id,
        chapter: chapter,
        url: URL(string: "https://example.com/audio/7/\(chapter).mp3")!,
        durationSeconds: 300
    )
    return NowPlayingItem(reciter: meaningReciter, chapter: chapter, chapterName: "Chapter \(chapter)", audio: audio)
}

/// Nine ayahs over 300 seconds: 0-12, 12-40, 40-70, 70-100, 100-150, 150-200, 200-240, 240-270, 270-300.
private func meaningTimings(chapter: Int) -> SurahTimings {
    let bounds: [Double] = [0, 12, 40, 70, 100, 150, 200, 240, 270, 300]
    let ayahs = (1..<bounds.count).map { index in
        AyahTiming(ayah: index, start: bounds[index - 1], end: bounds[index], words: [])
    }
    return SurahTimings(reciterID: meaningReciter.id, chapter: chapter, ayahs: ayahs)
}

private func placeholderMeaning(_ ayah: Int) -> AyahMeaning {
    AyahMeaning(text: "Placeholder meaning number \(ayah).", source: "Test Translation")
}

/// A string made of the given code points, built at run time.
private func textFromScalars(_ values: [UInt32]) -> String {
    var view = String.UnicodeScalarView()
    for value in values {
        if let scalar = Unicode.Scalar(value) {
            view.append(scalar)
        }
    }
    return String(view)
}

private struct MeaningTimingProvider: SurahTimingProviding {
    func timings(reciterID: Int, chapter: Int) async -> SurahTimings? {
        meaningTimings(chapter: chapter)
    }
}

private struct FixedMeaningProvider: AyahMeaningProviding {
    let meanings: [Int: AyahMeaning]

    func meaning(chapter: Int, ayah: Int) async -> AyahMeaning? {
        meanings[ayah]
    }
}

/// Holds every lookup until `release()`, so a test can end an ayah before its meaning arrives.
private final class GatedMeaningProvider: AyahMeaningProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let meanings: [Int: AyahMeaning]
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(meanings: [Int: AyahMeaning]) {
        self.meanings = meanings
    }

    func meaning(chapter: Int, ayah: Int) async -> AyahMeaning? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumesNow = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if resumesNow { continuation.resume() }
        }
        return meanings[ayah]
    }

    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let list = waiters
            waiters = []
            return list
        }
        for continuation in waiting {
            continuation.resume()
        }
    }
}

private final class MeaningQueue: ListenQueueResolving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Int] = []

    var requested: [Int] {
        lock.withLock { asked }
    }

    func item(chapter: Int, reciter: Reciter) async throws -> NowPlayingItem {
        lock.withLock { asked.append(chapter) }
        return meaningItem(chapter: chapter)
    }
}

/// Records recite after me waits so a test can end them by hand.
private final class MeaningWaitRecorder {
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

final class ListenMeaningTests: XCTestCase {
    private static let suiteName = "ListenMeaningTests"

    private struct Harness {
        let player: ListenPlayer
        let engine: SimulatedEngine
        let speaker: SimulatedMeaningSpeaker
        let defaults: UserDefaults
        let waits: MeaningWaitRecorder
    }

    @MainActor
    private func makeHarness(
        meanings: [Int: AyahMeaning]? = Dictionary(uniqueKeysWithValues: (1...9).map { ($0, placeholderMeaning($0)) }),
        provider: (any AyahMeaningProviding)? = nil,
        timings: Bool = true,
        readsMeaning: Bool = true
    ) -> Harness {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        let engine = SimulatedEngine(defaultDuration: 300)
        let speaker = SimulatedMeaningSpeaker()
        let player = ListenPlayer(engine: engine, system: QuietListenSystem(), speaker: speaker, defaults: defaults)
        let waits = MeaningWaitRecorder()
        player.scheduleWait = { seconds, action in
            waits.record(seconds, action)
        }
        if timings {
            player.timingProvider = MeaningTimingProvider()
        }
        if let provider {
            player.meaningProvider = provider
        } else if let meanings {
            player.meaningProvider = FixedMeaningProvider(meanings: meanings)
        }
        player.modes.readsMeaning = readsMeaning
        return Harness(player: player, engine: engine, speaker: speaker, defaults: defaults, waits: waits)
    }

    /// Plays chapter 1 with its timings and the first ayah's meaning ready.
    @MainActor
    private func start(_ h: Harness) async {
        h.player.play(meaningItem(chapter: 1))
        await h.player.timingsLoadFinished()
        await h.player.meaningLookupFinished()
    }

    // MARK: - Speaks after each ayah, then resumes

    @MainActor
    func testSpeaksAfterEachAyahThenResumes() async {
        let h = makeHarness()
        await start(h)
        XCTAssertNil(h.player.speakingMeaning)

        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(1).text])
        XCTAssertEqual(h.player.speakingMeaning, placeholderMeaning(1))
        XCTAssertFalse(h.engine.isPlaying)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)

        // The recitation stays paused while the voice reads.
        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.position, 12, accuracy: 0.001)

        await h.player.meaningLookupFinished()
        h.speaker.finish()
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertTrue(h.engine.isPlaying)

        h.engine.tick(by: 28)
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(1).text, placeholderMeaning(2).text])
        XCTAssertEqual(h.player.speakingMeaning, placeholderMeaning(2))
        XCTAssertEqual(h.player.position, 40, accuracy: 0.001)
        XCTAssertEqual(h.speaker.stopCount, 0)
    }

    @MainActor
    func testWaitsForAMeaningThatIsNotReadyYet() async {
        let gated = GatedMeaningProvider(meanings: [1: placeholderMeaning(1)])
        let h = makeHarness(provider: gated)
        h.player.play(meaningItem(chapter: 1))
        await h.player.timingsLoadFinished()

        h.engine.tick(by: 12)
        XCTAssertFalse(h.engine.isPlaying)
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertEqual(h.player.state, .playing)

        gated.release()
        await h.player.meaningLookupFinished()
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(1).text])
        XCTAssertEqual(h.player.speakingMeaning, placeholderMeaning(1))

        h.speaker.finish()
        XCTAssertTrue(h.engine.isPlaying)
    }

    @MainActor
    func testTheLastAyahsMeaningIsReadBeforeTheSurahEnds() async {
        let queue = MeaningQueue()
        let h = makeHarness()
        h.player.queueResolver = queue
        h.player.modes.surahEnd = .playNext
        await start(h)
        h.player.seek(to: 280)
        await h.player.meaningLookupFinished()

        h.engine.tick(by: 20)
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(9).text])
        XCTAssertEqual(queue.requested, [])

        h.speaker.finish()
        await h.player.queueLookupFinished()
        XCTAssertEqual(queue.requested, [2])
        XCTAssertEqual(h.player.item?.chapter, 2)
        XCTAssertEqual(h.player.state, .playing)
    }

    // MARK: - Order with ayah repeat and recite after me

    @MainActor
    func testOrderIsRepeatsThenMeaningThenTheListenersTurn() async {
        let h = makeHarness()
        h.player.modes.ayahRepeat = 2
        h.player.modes.reciteAfterMe = true
        await start(h)

        // First play of ayah 1: no meaning yet, the listener's turn as before.
        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [12])
        XCTAssertEqual(h.player.position, 0, accuracy: 0.001)
        h.waits.finishLast()

        // Last play: the meaning first, with no turn yet.
        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(1).text])
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [12])
        XCTAssertFalse(h.engine.isPlaying)

        // Then the listener's turn, as long as the ayah.
        h.speaker.finish()
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [12, 12])
        XCTAssertFalse(h.engine.isPlaying)

        // Then the next ayah.
        h.waits.finishLast()
        XCTAssertFalse(h.player.isWaitingForListener)
        XCTAssertTrue(h.engine.isPlaying)
        h.engine.tick(by: 3)
        XCTAssertEqual(h.player.position, 15, accuracy: 0.001)
    }

    // MARK: - No meaning

    @MainActor
    func testNoMeaningForAnAyahJustContinues() async {
        let h = makeHarness(meanings: [2: placeholderMeaning(2)])
        await start(h)

        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertTrue(h.engine.isPlaying)
        XCTAssertNil(h.player.speakingMeaning)

        await h.player.meaningLookupFinished()
        h.engine.tick(by: 28)
        XCTAssertEqual(h.speaker.spoken, [placeholderMeaning(2).text])
    }

    @MainActor
    func testNoMeaningGoesStraightToTheListenersTurn() async {
        let h = makeHarness(meanings: [:])
        h.player.modes.reciteAfterMe = true
        await start(h)
        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertTrue(h.player.isWaitingForListener)
        XCTAssertEqual(h.waits.seconds, [12])
    }

    @MainActor
    func testANilMeaningThatArrivesLateContinues() async {
        let gated = GatedMeaningProvider(meanings: [:])
        let h = makeHarness(provider: gated)
        h.player.play(meaningItem(chapter: 1))
        await h.player.timingsLoadFinished()
        h.engine.tick(by: 12)
        XCTAssertFalse(h.engine.isPlaying)

        gated.release()
        await h.player.meaningLookupFinished()
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertTrue(h.engine.isPlaying)
    }

    @MainActor
    func testOffWithoutAProviderOrWithoutTimingsNothingIsRead() async {
        let off = makeHarness(readsMeaning: false)
        await start(off)
        off.engine.tick(by: 12)
        XCTAssertEqual(off.speaker.spoken, [])
        XCTAssertTrue(off.engine.isPlaying)

        let noProvider = makeHarness(meanings: nil)
        await start(noProvider)
        noProvider.engine.tick(by: 12)
        XCTAssertEqual(noProvider.speaker.spoken, [])
        XCTAssertTrue(noProvider.engine.isPlaying)

        let noTimings = makeHarness(timings: false)
        await start(noTimings)
        noTimings.engine.tick(by: 12)
        XCTAssertEqual(noTimings.speaker.spoken, [])
        XCTAssertTrue(noTimings.engine.isPlaying)
    }

    // MARK: - Pause, stop, seek, skip and a new play stop the voice at once

    @MainActor
    private func speakingHarness() async -> Harness {
        let h = makeHarness()
        await start(h)
        h.engine.tick(by: 12)
        XCTAssertTrue(h.speaker.isSpeaking)
        XCTAssertNotNil(h.player.speakingMeaning)
        return h
    }

    @MainActor
    func testPauseStopsTheVoice() async {
        let h = await speakingHarness()
        h.player.pause()
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertFalse(h.speaker.isSpeaking)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertEqual(h.player.state, .paused)

        // A late finish does nothing.
        h.speaker.finish()
        XCTAssertFalse(h.engine.isPlaying)

        h.player.resume()
        XCTAssertTrue(h.engine.isPlaying)
        h.engine.tick(by: 3)
        XCTAssertEqual(h.player.position, 15, accuracy: 0.001)
        XCTAssertEqual(h.speaker.spoken.count, 1)
    }

    @MainActor
    func testStopStopsTheVoice() async {
        let h = await speakingHarness()
        h.player.stop()
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertEqual(h.player.state, .idle)
    }

    @MainActor
    func testSeekAndSkipStopTheVoiceAndPlayFromThere() async {
        let h = await speakingHarness()
        h.player.seek(to: 50)
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertTrue(h.engine.isPlaying)
        XCTAssertEqual(h.player.position, 50, accuracy: 0.001)

        let again = await speakingHarness()
        again.player.skip(by: 15)
        XCTAssertEqual(again.speaker.stopCount, 1)
        XCTAssertNil(again.player.speakingMeaning)
        XCTAssertTrue(again.engine.isPlaying)
        XCTAssertEqual(again.player.position, 27, accuracy: 0.001)
    }

    @MainActor
    func testANewPlayStopsTheVoice() async {
        let h = await speakingHarness()
        h.player.play(meaningItem(chapter: 2))
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertEqual(h.player.item?.chapter, 2)
    }

    @MainActor
    func testPauseForPrayerWinsOverTheVoice() async {
        let h = await speakingHarness()
        h.player.prayerTimeArrived(name: "Asr")
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.pausedForPrayer, "Asr")
    }

    @MainActor
    func testSleepAtTheEndOfTheSurahWaitsForTheLastMeaningThenPauses() async {
        let queue = MeaningQueue()
        let h = makeHarness()
        h.player.queueResolver = queue
        h.player.modes.surahEnd = .playNext
        await start(h)
        h.player.sleepAtEndOfSurah()
        h.player.seek(to: 280)
        await h.player.meaningLookupFinished()

        h.engine.tick(by: 20)
        XCTAssertTrue(h.speaker.isSpeaking)
        h.speaker.finish()
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(queue.requested, [])
    }

    @MainActor
    func testSkipMeaningAndTurningTheModeOffGoOn() async {
        let h = await speakingHarness()
        h.player.skipMeaning()
        XCTAssertEqual(h.speaker.stopCount, 1)
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertTrue(h.engine.isPlaying)

        let off = await speakingHarness()
        off.player.modes.readsMeaning = false
        XCTAssertEqual(off.speaker.stopCount, 1)
        XCTAssertNil(off.player.speakingMeaning)
        XCTAssertTrue(off.engine.isPlaying)
    }

    // MARK: - Never a computer voice for Arabic

    func testArabicScriptIsNeverSpeakable() {
        // A letter from each Arabic block, built from code points.
        let samples: [UInt32] = [0x0628, 0x0750, 0x0870, 0x08A0, 0xFB50, 0xFE8F, 0x10E60, 0x10EC2, 0x1EC71, 0x1ED01, 0x1EE01]
        for value in samples {
            let text = textFromScalars([value])
            XCTAssertTrue(ListenMeaningText.containsArabicScript(text), "U+\(String(value, radix: 16))")
            XCTAssertFalse(ListenMeaningText.isSpeakable(text), "U+\(String(value, radix: 16))")
            XCTAssertFalse(ListenMeaningText.isSpeakable("In the English text " + text + " here"))
        }
        for range in ListenMeaningText.arabicScriptRanges {
            XCTAssertTrue(ListenMeaningText.containsArabicScript(textFromScalars([range.lowerBound])))
            XCTAssertTrue(ListenMeaningText.containsArabicScript(textFromScalars([range.upperBound])))
        }
        // Just outside the Arabic block, and plain English, are not Arabic.
        XCTAssertFalse(ListenMeaningText.containsArabicScript(textFromScalars([0x05FF])))
        XCTAssertFalse(ListenMeaningText.containsArabicScript(textFromScalars([0x0700])))
        XCTAssertTrue(ListenMeaningText.isSpeakable("Placeholder meaning, with (notes) and 12 digits."))
        XCTAssertFalse(ListenMeaningText.isSpeakable(""))
        XCTAssertFalse(ListenMeaningText.isSpeakable("  ...  "))
    }

    @MainActor
    func testAMeaningWithArabicScriptIsNotReadAndPlaybackGoesOn() async {
        let mixed = AyahMeaning(text: "Placeholder " + textFromScalars([0x0627, 0x0644]) + " meaning", source: "Test Translation")
        let h = makeHarness(meanings: [1: mixed, 2: placeholderMeaning(2)])
        await start(h)
        h.engine.tick(by: 12)
        XCTAssertEqual(h.speaker.spoken, [])
        XCTAssertNil(h.player.speakingMeaning)
        XCTAssertTrue(h.engine.isPlaying)
    }

    // MARK: - Voice and label

    func testVoiceLanguagesAreEnglishOnly() {
        XCTAssertEqual(ListenMeaningText.voiceLanguages(preferred: ["fr-FR", "en-GB", "en-US"]), ["en-GB", "en-US"])
        XCTAssertEqual(ListenMeaningText.voiceLanguages(preferred: ["fr-FR", "de-DE"]), ["en-US"])
        XCTAssertEqual(ListenMeaningText.voiceLanguages(preferred: []), ["en-US"])
        XCTAssertTrue(ListenMeaningText.isEnglish("en"))
        XCTAssertTrue(ListenMeaningText.isEnglish("EN-au"))
        XCTAssertFalse(ListenMeaningText.isEnglish("eng"))
        XCTAssertFalse(ListenMeaningText.isEnglish("fr-FR"))
    }

    func testLabelNamesTheSource() {
        XCTAssertEqual(ListenMeaningText.label(for: placeholderMeaning(1)), "Meaning \u{00B7} Test Translation")
    }

    // MARK: - Mode persistence

    @MainActor
    func testReadsMeaningIsSavedAndOlderSavedModesStillLoad() throws {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)

        var older = PlayModes()
        older.surahEnd = .playNext
        older.ayahRepeat = 3
        older.reciteAfterMe = true
        older.pausesForPrayer = false
        let data = try JSONEncoder().encode(older)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["readsMeaning"])
        object.removeValue(forKey: "readsMeaning")
        let olderData = try JSONSerialization.data(withJSONObject: object)
        defaults.set(olderData, forKey: ListenPlayer.modesKey)

        let player = ListenPlayer(engine: SimulatedEngine(), defaults: defaults)
        XCTAssertFalse(player.modes.readsMeaning)
        XCTAssertEqual(player.modes.surahEnd, .playNext)
        XCTAssertEqual(player.modes.ayahRepeat, 3)
        XCTAssertTrue(player.modes.reciteAfterMe)
        XCTAssertFalse(player.modes.pausesForPrayer)

        player.modes.readsMeaning = true
        let reloaded = ListenPlayer(engine: SimulatedEngine(), defaults: defaults)
        XCTAssertTrue(reloaded.modes.readsMeaning)
        XCTAssertEqual(reloaded.modes.ayahRepeat, 3)
    }
}
