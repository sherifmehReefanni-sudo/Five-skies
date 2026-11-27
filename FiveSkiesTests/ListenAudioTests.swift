import XCTest
@testable import FiveSkies

@MainActor
private final class RecordingListenSystem: ListenSystemHooks {
    var activates = true
    private(set) var activateCount = 0
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var lastInfo: ListenNowPlayingInfo?

    func activateSession() -> Bool {
        activateCount += 1
        return activates
    }

    func connect(to player: ListenPlayer) {
        connectCount += 1
    }

    func disconnect() {
        disconnectCount += 1
    }

    func updateNowPlaying(_ info: ListenNowPlayingInfo?) {
        lastInfo = info
    }
}

private final class ListenTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

final class ListenAudioTests: XCTestCase {
    private struct Harness {
        let player: ListenPlayer
        let engine: SimulatedEngine
        let system: RecordingListenSystem
        let clock: ListenTestClock
    }

    @MainActor
    private func makeHarness() -> Harness {
        let engine = SimulatedEngine(defaultDuration: 300)
        let system = RecordingListenSystem()
        let clock = ListenTestClock()
        let player = ListenPlayer(engine: engine, system: system, now: { clock.now })
        return Harness(player: player, engine: engine, system: system, clock: clock)
    }

    private func item(chapter: Int = 1, duration: Double? = 300) -> NowPlayingItem {
        let reciter = Reciter(id: 7, name: "Test Reciter", style: nil)
        let audio = ChapterAudio(
            reciterID: 7,
            chapter: chapter,
            url: URL(string: "https://example.com/audio/\(chapter).mp3")!,
            durationSeconds: duration
        )
        return NowPlayingItem(reciter: reciter, chapter: chapter, chapterName: "Chapter \(chapter)", audio: audio)
    }

    // MARK: - Play, pause, resume

    @MainActor
    func testPlayStartsPlayingAndFillsTheLockScreen() {
        let h = makeHarness()
        h.player.play(item())

        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.item, item())
        XCTAssertEqual(h.player.duration, 300)
        XCTAssertEqual(h.engine.loadedURL, URL(string: "https://example.com/audio/1.mp3"))
        XCTAssertTrue(h.engine.isPlaying)
        XCTAssertEqual(h.system.activateCount, 1)
        XCTAssertEqual(h.system.connectCount, 1)

        let info = h.system.lastInfo
        XCTAssertEqual(info?.title, "Chapter 1")
        XCTAssertEqual(info?.artist, "Test Reciter")
        XCTAssertEqual(info?.album, "Quran Foundation")
        XCTAssertEqual(info?.duration, 300)
        XCTAssertEqual(info?.rate, 1)
    }

    @MainActor
    func testUnknownDurationComesFromTheEngine() {
        let h = makeHarness()
        h.player.play(item(duration: nil))
        XCTAssertEqual(h.player.duration, 300)
    }

    @MainActor
    func testPauseAndResume() {
        let h = makeHarness()
        h.player.play(item())
        h.engine.tick(by: 10)
        XCTAssertEqual(h.player.position, 10, accuracy: 0.001)

        h.player.pause()
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertFalse(h.engine.isPlaying)
        XCTAssertEqual(h.system.lastInfo?.rate, 0)
        h.engine.tick(by: 10)
        XCTAssertEqual(h.player.position, 10, accuracy: 0.001)

        h.player.resume()
        XCTAssertEqual(h.player.state, .playing)
        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.position, 15, accuracy: 0.001)
    }

    @MainActor
    func testTogglePlayPause() {
        let h = makeHarness()
        h.player.play(item())
        h.player.togglePlayPause()
        XCTAssertEqual(h.player.state, .paused)
        h.player.togglePlayPause()
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testPlayingTheSameItemAgainDoesNotReload() {
        let h = makeHarness()
        h.player.play(item())
        h.engine.tick(by: 20)
        h.player.pause()
        h.player.play(item())
        XCTAssertEqual(h.engine.loadCount, 1)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 20, accuracy: 0.001)

        h.player.play(item(chapter: 2))
        XCTAssertEqual(h.engine.loadCount, 2)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.item?.chapter, 2)
    }

    @MainActor
    func testSeekAndSkipStayInsideTheSurah() {
        let h = makeHarness()
        h.player.play(item())
        h.player.seek(to: 100)
        XCTAssertEqual(h.player.position, 100)
        h.player.skip(by: 15)
        XCTAssertEqual(h.player.position, 115)
        h.player.skip(by: -200)
        XCTAssertEqual(h.player.position, 0)
        h.player.seek(to: 1_000)
        XCTAssertEqual(h.player.position, 300)
        XCTAssertEqual(h.engine.position, 300)
    }

    // MARK: - Speed

    @MainActor
    func testRateIsClampedToAllowedSpeeds() {
        XCTAssertEqual(ListenPlayer.nearestAllowedRate(3), 2)
        XCTAssertEqual(ListenPlayer.nearestAllowedRate(0.1), 0.75)
        XCTAssertEqual(ListenPlayer.nearestAllowedRate(1.3), 1.25)
        XCTAssertEqual(ListenPlayer.nearestAllowedRate(1.6), 1.5)
        XCTAssertEqual(ListenPlayer.nearestAllowedRate(.nan), 1)

        let h = makeHarness()
        h.player.play(item())
        h.player.setRate(5)
        XCTAssertEqual(h.player.rate, 2)
        XCTAssertEqual(h.engine.rate, 2)
        XCTAssertEqual(h.system.lastInfo?.rate, 2)
        h.engine.tick(by: 10)
        XCTAssertEqual(h.player.position, 20, accuracy: 0.001)

        h.player.setRate(0.5)
        XCTAssertEqual(h.player.rate, 0.75)
    }

    @MainActor
    func testRateCarriesToTheNextSurah() {
        let h = makeHarness()
        h.player.setRate(1.5)
        h.player.play(item())
        XCTAssertEqual(h.engine.rate, 1.5)
    }

    // MARK: - Loops

    @MainActor
    func testSurahEndsPausedAtTheStartWithoutLoop() {
        let h = makeHarness()
        h.player.play(item())
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertNotNil(h.player.item)
    }

    @MainActor
    func testLoopSurahRestartsAtTheEnd() {
        let h = makeHarness()
        h.player.loopsSurah = true
        h.player.play(item())
        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertTrue(h.engine.isPlaying)
        h.engine.tick(by: 4)
        XCTAssertEqual(h.player.position, 4, accuracy: 0.001)
    }

    @MainActor
    func testLoopRangeJumpsBackToItsStart() {
        let h = makeHarness()
        h.player.play(item())
        h.engine.tick(by: 5)

        h.player.setLoopRange(10.0...20.0)
        XCTAssertEqual(h.player.loopRange, 10.0...20.0)
        XCTAssertEqual(h.player.position, 10)

        h.engine.tick(by: 5)
        XCTAssertEqual(h.player.position, 15, accuracy: 0.001)
        h.engine.tick(by: 6)
        XCTAssertEqual(h.player.position, 10, accuracy: 0.001)
        XCTAssertEqual(h.engine.position, 10, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)

        h.player.setLoopRange(nil)
        XCTAssertNil(h.player.loopRange)
    }

    @MainActor
    func testLoopRangeIsCheckedAndClearedForANewSurah() {
        let h = makeHarness()
        h.player.play(item())
        h.player.setLoopRange(400.0...500.0)
        XCTAssertNil(h.player.loopRange)

        h.player.setLoopRange(290.0...400.0)
        XCTAssertEqual(h.player.loopRange, 290.0...300.0)
        h.engine.tick(by: 10)
        XCTAssertEqual(h.player.position, 290, accuracy: 0.001)
        XCTAssertEqual(h.player.state, .playing)

        h.player.play(item(chapter: 2))
        XCTAssertNil(h.player.loopRange)
    }

    // MARK: - Sleep timer

    @MainActor
    func testSleepTimerPausesAfterTheMinutesWithAFade() {
        let h = makeHarness()
        h.player.play(item())
        h.player.setSleepTimer(minutes: 5)
        XCTAssertEqual(h.player.sleepTimerEnd, h.clock.now.addingTimeInterval(300))

        h.clock.now = h.clock.now.addingTimeInterval(299)
        h.engine.tick(by: 1)
        XCTAssertEqual(h.player.state, .playing)

        h.clock.now = h.clock.now.addingTimeInterval(2)
        h.engine.tick(by: 1)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertNil(h.player.sleepTimerEnd)
        XCTAssertEqual(h.engine.fadeCount, 1)
        XCTAssertFalse(h.engine.isPlaying)
    }

    @MainActor
    func testSleepTimerCancels() {
        let h = makeHarness()
        h.player.play(item())
        h.player.setSleepTimer(minutes: 5)
        h.player.setSleepTimer(minutes: nil)
        XCTAssertNil(h.player.sleepTimerEnd)
        h.clock.now = h.clock.now.addingTimeInterval(600)
        h.engine.tick(by: 1)
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.engine.fadeCount, 0)
    }

    @MainActor
    func testExpiredSleepTimerDoesNotStopAResume() {
        let h = makeHarness()
        h.player.play(item())
        h.player.setSleepTimer(minutes: 1)
        h.player.pause()
        h.clock.now = h.clock.now.addingTimeInterval(120)
        h.player.resume()
        XCTAssertNil(h.player.sleepTimerEnd)
        h.engine.tick(by: 1)
        XCTAssertEqual(h.player.state, .playing)
    }

    @MainActor
    func testSleepAtEndOfSurahWinsOverLoop() {
        let h = makeHarness()
        h.player.loopsSurah = true
        h.player.play(item())
        h.player.sleepAtEndOfSurah()
        XCTAssertTrue(h.player.sleepsAtEndOfSurah)

        h.engine.tick(by: 300)
        XCTAssertEqual(h.player.state, .paused)
        XCTAssertFalse(h.player.sleepsAtEndOfSurah)
        XCTAssertFalse(h.engine.isPlaying)
    }

    @MainActor
    func testSleepTimerKindsReplaceEachOther() {
        let h = makeHarness()
        h.player.play(item())
        h.player.sleepAtEndOfSurah()
        h.player.setSleepTimer(minutes: 10)
        XCTAssertFalse(h.player.sleepsAtEndOfSurah)
        XCTAssertNotNil(h.player.sleepTimerEnd)

        h.player.sleepAtEndOfSurah()
        XCTAssertNil(h.player.sleepTimerEnd)
        XCTAssertTrue(h.player.sleepsAtEndOfSurah)
    }

    // MARK: - Stop and failure

    @MainActor
    func testStopClearsTheItemAndTheLockScreen() {
        let h = makeHarness()
        h.player.play(item())
        h.player.setSleepTimer(minutes: 5)
        h.player.setLoopRange(10.0...20.0)
        h.engine.tick(by: 3)
        h.player.stop()

        XCTAssertNil(h.player.item)
        XCTAssertEqual(h.player.state, .idle)
        XCTAssertEqual(h.player.position, 0)
        XCTAssertEqual(h.player.duration, 0)
        XCTAssertNil(h.player.loopRange)
        XCTAssertNil(h.player.sleepTimerEnd)
        XCTAssertNil(h.system.lastInfo)
        XCTAssertEqual(h.system.disconnectCount, 1)
        XCTAssertNil(h.engine.loadedURL)
    }

    @MainActor
    func testLoadFailureShowsAPlainMessage() {
        let h = makeHarness()
        h.engine.failsOnLoad = true
        h.player.play(item())
        XCTAssertEqual(h.player.state, .failed("Could not play this recitation. Check your connection."))
        XCTAssertFalse(h.engine.isPlaying)
    }

    @MainActor
    func testFailureDuringPlaybackAndRetry() {
        let h = makeHarness()
        h.player.play(item())
        h.engine.tick(by: 30)
        h.engine.simulateFailure()
        XCTAssertEqual(h.player.state, .failed(ListenPlayer.failureMessage))

        h.player.resume()
        XCTAssertEqual(h.player.state, .playing)
        XCTAssertEqual(h.engine.loadCount, 2)
        XCTAssertEqual(h.player.position, 30, accuracy: 0.001)
    }

    @MainActor
    func testSessionRefusalIsAFailure() {
        let h = makeHarness()
        h.system.activates = false
        h.player.play(item())
        XCTAssertEqual(h.player.state, .failed(ListenPlayer.failureMessage))
        XCTAssertEqual(h.engine.loadCount, 0)
    }

    // MARK: - Interruptions and route changes

    @MainActor
    func testInterruptionPausesAndResumesWhenAllowed() {
        let h = makeHarness()
        h.player.play(item())
        h.player.interruptionBegan()
        XCTAssertEqual(h.player.state, .paused)
        h.player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(h.player.state, .playing)

        h.player.interruptionBegan()
        h.player.interruptionEnded(shouldResume: false)
        XCTAssertEqual(h.player.state, .paused)
    }

    @MainActor
    func testInterruptionDoesNotStartAPausedPlayer() {
        let h = makeHarness()
        h.player.play(item())
        h.player.pause()
        h.player.interruptionBegan()
        h.player.interruptionEnded(shouldResume: true)
        XCTAssertEqual(h.player.state, .paused)
    }

    @MainActor
    func testUnpluggingHeadphonesPauses() {
        let h = makeHarness()
        h.player.play(item())
        h.player.outputDeviceRemoved()
        XCTAssertEqual(h.player.state, .paused)
    }
}
