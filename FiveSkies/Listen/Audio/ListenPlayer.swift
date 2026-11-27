import Foundation

/// The one player for the app. Streams a surah, and handles speed, loop surah,
/// an A to B loop range, the sleep timer, interruptions and the lock screen.
/// The sound comes from a `PlaybackEngine`; the lock screen and audio session from `ListenSystemHooks`.
@MainActor
final class ListenPlayer: ObservableObject {
    static let allowedRates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    static let failureMessage = "Could not play this recitation. Check your connection."
    /// How long the sleep timer fades out before it pauses.
    static let sleepFadeSeconds: Double = 3

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var item: NowPlayingItem?
    /// Seconds from the start of the surah.
    @Published private(set) var position: Double = 0
    /// Seconds; zero until known.
    @Published private(set) var duration: Double = 0
    @Published private(set) var rate: Float = 1
    /// Plays the surah again from the start when it ends.
    @Published var loopsSurah = false
    /// Plays this part of the surah again and again, in seconds. Cleared when a new surah starts.
    @Published private(set) var loopRange: ClosedRange<Double>?
    /// When the sleep timer will pause playback, if it is set in minutes.
    @Published private(set) var sleepTimerEnd: Date?
    /// True when the sleep timer is set to the end of the surah.
    @Published private(set) var sleepsAtEndOfSurah = false

    private let engine: PlaybackEngine
    private let system: ListenSystemHooks
    private let now: () -> Date
    /// True from play or resume until pause, stop, the end or a failure.
    private var wantsToPlay = false
    private var wasPlayingBeforeInterruption = false
    private var isSleepFading = false
    private var sleepTask: Task<Void, Never>?

    init(engine: PlaybackEngine, system: ListenSystemHooks? = nil, now: @escaping () -> Date = { Date() }) {
        self.engine = engine
        self.system = system ?? QuietListenSystem()
        self.now = now
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    /// The player the app uses: the simulated engine under `-FSFakeListen`, AVPlayer otherwise.
    static func live(processInfo: ProcessInfo = .processInfo) -> ListenPlayer {
        if ListenLaunch.usesFakes(processInfo: processInfo) {
            return ListenPlayer(engine: SimulatedEngine(autoAdvances: true), system: QuietListenSystem())
        }
        return ListenPlayer(engine: AVPlayerEngine(), system: LiveListenSystem())
    }

    var isPlaying: Bool { state == .playing }

    // MARK: - Transport

    /// Starts `item` from the beginning. The same item again only resumes it.
    func play(_ item: NowPlayingItem) {
        if item == self.item, state != .idle, !isFailed {
            if !wantsToPlay { resume() }
            return
        }
        endSleepFade()
        engine.stop()
        self.item = item
        position = 0
        duration = item.audio.durationSeconds ?? 0
        loopRange = nil
        state = .loading
        wantsToPlay = true
        guard system.activateSession() else {
            fail()
            return
        }
        system.connect(to: self)
        engine.load(url: item.audio.url, expectedDuration: item.audio.durationSeconds)
        // The engine may have reported a failure while loading.
        guard wantsToPlay else { return }
        engine.play(rate: rate)
        refreshNowPlaying()
    }

    func pause() {
        guard item != nil else { return }
        endSleepFade()
        wantsToPlay = false
        engine.pause()
        if !isFailed {
            state = .paused
        }
        refreshNowPlaying()
    }

    func resume() {
        guard let item else { return }
        if isFailed {
            // Try the same surah again from where it was.
            let resumeAt = position
            self.item = nil
            play(item)
            if resumeAt > 0, wantsToPlay { seek(to: resumeAt) }
            return
        }
        guard !wantsToPlay else { return }
        endSleepFade()
        if let end = sleepTimerEnd, now() >= end {
            cancelSleepTimer()
        }
        guard system.activateSession() else {
            fail()
            return
        }
        system.connect(to: self)
        wantsToPlay = true
        state = .playing
        engine.play(rate: rate)
        refreshNowPlaying()
    }

    func togglePlayPause() {
        if wantsToPlay {
            pause()
        } else {
            resume()
        }
    }

    func seek(to seconds: Double) {
        guard item != nil, !isFailed else { return }
        var target = max(0, seconds)
        if duration > 0 { target = min(target, duration) }
        position = target
        engine.seek(to: target)
        refreshNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    /// Picks the nearest allowed speed (0.75, 1, 1.25, 1.5 or 2).
    func setRate(_ requested: Float) {
        let nearest = Self.nearestAllowedRate(requested)
        guard nearest != rate else { return }
        rate = nearest
        engine.setRate(nearest)
        refreshNowPlaying()
    }

    static func nearestAllowedRate(_ requested: Float) -> Float {
        guard requested.isFinite else { return 1 }
        return allowedRates.min { abs($0 - requested) < abs($1 - requested) } ?? 1
    }

    /// Loops from the start of the range to its end. Nil clears it. A range that is
    /// empty or outside the surah clears it too. Jumps to the start if playback is outside it.
    func setLoopRange(_ range: ClosedRange<Double>?) {
        guard let range, item != nil else {
            loopRange = nil
            return
        }
        let lower = max(0, range.lowerBound)
        var upper = range.upperBound
        if duration > 0 { upper = min(upper, duration) }
        guard upper > lower else {
            loopRange = nil
            return
        }
        loopRange = lower...upper
        if position < lower || position >= upper {
            seek(to: lower)
        }
    }

    /// Pauses after `minutes` with a short fade. Nil or zero cancels any sleep timer.
    func setSleepTimer(minutes: Int?) {
        cancelSleepTimer()
        guard let minutes, minutes > 0 else { return }
        let end = now().addingTimeInterval(Double(minutes) * 60)
        sleepTimerEnd = end
        let delay = end.timeIntervalSince(now())
        sleepTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.checkSleepTimer()
        }
    }

    /// Pauses when the current surah ends, instead of a set number of minutes.
    func sleepAtEndOfSurah() {
        cancelSleepTimer()
        sleepsAtEndOfSurah = true
    }

    /// Stops playback, clears the surah and removes the lock screen controls.
    func stop() {
        endSleepFade()
        cancelSleepTimer()
        wantsToPlay = false
        wasPlayingBeforeInterruption = false
        engine.stop()
        item = nil
        state = .idle
        position = 0
        duration = 0
        loopRange = nil
        system.updateNowPlaying(nil)
        system.disconnect()
    }

    // MARK: - System events (from ListenSystemHooks)

    func interruptionBegan() {
        wasPlayingBeforeInterruption = wantsToPlay
        if wantsToPlay { pause() }
    }

    func interruptionEnded(shouldResume: Bool) {
        let resumes = shouldResume && wasPlayingBeforeInterruption
        wasPlayingBeforeInterruption = false
        if resumes { resume() }
    }

    /// Headphones were unplugged or a Bluetooth device went away.
    func outputDeviceRemoved() {
        if wantsToPlay { pause() }
    }

    // MARK: - Engine events

    private func handle(_ event: PlaybackEngineEvent) {
        guard item != nil else { return }
        switch event {
        case .ready(let known):
            if let known, known.isFinite, known > 0 {
                duration = known
            }
            refreshNowPlaying()
        case .buffering(let waiting):
            guard wantsToPlay else { return }
            let next: PlaybackState = waiting ? .loading : .playing
            if state != next {
                state = next
                refreshNowPlaying()
            }
        case .progress(let reported, let known):
            if let known, known.isFinite, known > 0, known != duration {
                duration = known
            }
            position = max(0, reported)
            if wantsToPlay, let range = loopRange, position >= range.upperBound {
                position = range.lowerBound
                engine.seek(to: range.lowerBound)
                refreshNowPlaying()
            }
            checkSleepTimer()
        case .ended:
            handleEnd()
        case .failed:
            fail()
        }
    }

    private func handleEnd() {
        if sleepsAtEndOfSurah {
            sleepsAtEndOfSurah = false
            finishAtStart()
            return
        }
        if let range = loopRange {
            restart(at: range.lowerBound)
            return
        }
        if loopsSurah {
            restart(at: 0)
            return
        }
        finishAtStart()
    }

    private func restart(at seconds: Double) {
        position = seconds
        engine.seek(to: seconds)
        wantsToPlay = true
        state = .playing
        engine.play(rate: rate)
        refreshNowPlaying()
    }

    /// The surah ended: paused and back at the start, ready to play again.
    private func finishAtStart() {
        wantsToPlay = false
        state = .paused
        position = 0
        engine.seek(to: 0)
        refreshNowPlaying()
    }

    private func fail() {
        endSleepFade()
        wantsToPlay = false
        engine.pause()
        state = .failed(Self.failureMessage)
        refreshNowPlaying()
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    // MARK: - Sleep timer

    private func checkSleepTimer() {
        guard let end = sleepTimerEnd, now() >= end else { return }
        cancelSleepTimer()
        guard wantsToPlay else { return }
        isSleepFading = true
        engine.fadeOut(over: Self.sleepFadeSeconds) { [weak self] in
            self?.finishSleepFade()
        }
    }

    private func finishSleepFade() {
        guard isSleepFading else { return }
        isSleepFading = false
        pause()
    }

    private func endSleepFade() {
        guard isSleepFading else { return }
        isSleepFading = false
        engine.cancelFade()
    }

    private func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerEnd = nil
        sleepsAtEndOfSurah = false
    }

    // MARK: - Lock screen

    private func refreshNowPlaying() {
        guard let item else {
            system.updateNowPlaying(nil)
            return
        }
        system.updateNowPlaying(ListenNowPlayingInfo(
            title: item.chapterName,
            artist: item.reciter.name,
            album: ListenNowPlayingInfo.album,
            elapsed: position,
            duration: duration,
            rate: state == .playing ? rate : 0,
            defaultRate: rate
        ))
    }
}
