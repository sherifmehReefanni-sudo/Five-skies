import Foundation

/// The one player for the app. Streams a surah, and handles speed, an A to B loop range,
/// the sleep timer, interruptions and the lock screen, plus the round C1 play modes:
/// what happens when a surah ends (stop, next, repeat, a set), ayah repeat, recite after me,
/// loop a range of ayahs, pause for prayer and resume where the listener stopped.
/// The sound comes from a `PlaybackEngine`; the lock screen and audio session from `ListenSystemHooks`.
@MainActor
final class ListenPlayer: ObservableObject {
    static let allowedRates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    static let failureMessage = "Could not play this recitation. Check your connection."
    /// How long the sleep timer fades out before it pauses.
    static let sleepFadeSeconds: Double = 3
    /// UserDefaults key for `modes`, saved as JSON.
    static let modesKey = "listen.playModes"
    /// UserDefaults key for the remembered spots, a JSON list of `ListenResumeEntry`, newest last.
    static let resumeKey = "listen.resume"
    /// How many surahs keep a remembered spot. The oldest is dropped first.
    static let resumeLimit = 50
    /// A remembered spot is used only when it is more than this many seconds from both ends.
    static let resumeMargin: Double = 10
    /// While playing, the spot is saved again each time playback has moved this many seconds.
    static let resumeSaveStep: Double = 5
    static let lastChapter = 114

    @Published private(set) var state: PlaybackState = .idle
    @Published private(set) var item: NowPlayingItem?
    /// Seconds from the start of the surah.
    @Published private(set) var position: Double = 0
    /// Seconds; zero until known.
    @Published private(set) var duration: Double = 0
    @Published private(set) var rate: Float = 1
    /// Plays this part of the surah again and again, in seconds. Cleared when a new surah starts.
    @Published private(set) var loopRange: ClosedRange<Double>?
    /// When the sleep timer will pause playback, if it is set in minutes.
    @Published private(set) var sleepTimerEnd: Date?
    /// True when the sleep timer is set to the end of the surah. It wins over every play mode.
    @Published private(set) var sleepsAtEndOfSurah = false

    /// The listener's play choices, saved as JSON under `modesKey` whenever they change.
    @Published var modes: PlayModes {
        didSet { modesDidChange(from: oldValue) }
    }
    /// Timings for the current surah, once loaded. Nil when there are none.
    @Published private(set) var timings: SurahTimings?
    /// False until usable timings arrive. Ayah repeat, recite after me, play from ayah and
    /// loop ayahs do nothing without them, so the UI greys them out.
    @Published private(set) var timingsAvailable = false
    /// The ayah playing now, from the timings. Nil between ayahs or without timings.
    @Published private(set) var currentAyah: Int?
    /// The Quran Foundation word position playing now, within `currentAyah`. Nil between words.
    @Published private(set) var currentWord: Int?
    /// Recite after me: the player is silent while the listener recites the ayah.
    @Published private(set) var isWaitingForListener = false
    /// The prayer name, when playback paused because its time arrived. Cleared on resume or stop.
    @Published private(set) var pausedForPrayer: String?
    /// The ayahs being looped, when the loop was set with `setLoopAyahs`.
    @Published private(set) var loopAyahs: ClosedRange<Int>?
    /// Repeat this surah: how many repeats have started (0 during the first play).
    @Published private(set) var surahRepeatsDone = 0
    /// The remembered spot this surah started from, so the UI can offer "Start over". Nil otherwise.
    @Published private(set) var resumedFrom: Double?

    /// Makes the next surah's item for play next and play a set. Set by the UI.
    /// Without it those modes stop at the end of the surah.
    var queueResolver: (any ListenQueueResolving)?
    /// Supplies timings. Set by the lead. Without it the ayah options stay off.
    var timingProvider: (any SurahTimingProviding)?
    /// Runs the recite after me wait. Tests replace it to end waits by hand.
    var scheduleWait: (Double, @escaping @MainActor @Sendable () -> Void) -> Void

    /// Compatibility for the B1 UI: true when the surah repeats. Setting it true picks
    /// "repeat until stopped"; setting it false while repeating goes back to stop.
    var loopsSurah: Bool {
        get {
            if case .repeatSurah = modes.surahEnd { return true }
            return false
        }
        set {
            if newValue {
                modes.surahEnd = .repeatSurah(times: nil)
            } else if loopsSurah {
                modes.surahEnd = .stop
            }
        }
    }

    private let engine: PlaybackEngine
    private let system: ListenSystemHooks
    private let defaults: UserDefaults
    private let now: () -> Date
    /// True from play or resume until pause, stop, the end or a failure.
    private var wantsToPlay = false
    private var wasPlayingBeforeInterruption = false
    private var isSleepFading = false
    private var sleepTask: Task<Void, Never>?

    // Queue
    private var queueTask: Task<Void, Never>?
    private var queueToken = 0
    /// The surah the queue is moving to. Kept after a failure or a pause so resume tries it again.
    private var pendingQueueChapter: Int?

    // Timings
    private var timingTask: Task<Void, Never>?
    private var timingToken = 0
    /// Play from ayah, waiting for the timings to arrive.
    private var pendingStartAyah: Int?

    // Ayah modes
    /// Index into `timings.ayahs` of the ayah playing, whose end has not been handled yet.
    private var pendingAyahIndex: Int?
    private var repeatingAyah: Int?
    private var ayahPlaysDone = 0
    private enum AfterWait { case play, endSurah }
    private var afterWait: AfterWait = .play
    private var waitToken = 0

    // Resume
    private var lastSavedPosition: Double = 0

    private enum StartPoint: Equatable {
        case beginning
        /// A remembered spot: sets `resumedFrom`.
        case resume(Double)
        /// Retry after a failure, at the same spot.
        case seconds(Double)
        case ayah(Int)
    }

    private struct AyahCrossing {
        let timing: AyahTiming
        let replayed: Bool
    }

    init(
        engine: PlaybackEngine,
        system: ListenSystemHooks? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.system = system ?? QuietListenSystem()
        self.defaults = defaults
        self.now = now
        self.modes = ListenPlayer.loadModes(from: defaults)
        self.scheduleWait = { seconds, action in
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanoseconds)
                action()
            }
        }
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

    /// Starts `item`, from its remembered spot when there is one (see `resumeMargin`).
    /// The same item again only resumes it; after a failure it tries again.
    func play(_ item: NowPlayingItem) {
        if item == self.item, isFailed {
            resume()
            return
        }
        if item == self.item, state != .idle {
            if !wantsToPlay { resume() }
            return
        }
        start(item, at: savedStart(for: item))
    }

    /// Starts `item` at the start of `ayah`. Waits (loading) for the timings first; without
    /// timings it plays from the beginning. For the item already playing it jumps there.
    func play(_ item: NowPlayingItem, fromAyah ayah: Int) {
        if item == self.item, state != .idle, !isFailed {
            if let ayahStart = ayahTiming(ayah)?.start {
                seek(to: ayahStart)
            } else if timingTask != nil {
                pendingStartAyah = ayah
            }
            if !wantsToPlay { resume() }
            return
        }
        start(item, at: timingProvider == nil ? .beginning : .ayah(ayah))
    }

    func pause() {
        guard item != nil else { return }
        endSleepFade()
        let surahWasEnding = isWaitingForListener && afterWait == .endSurah
        cancelListenerWait()
        if queueTask != nil {
            // Keeps pendingQueueChapter, so resume carries on to the next surah.
            cancelQueue()
        }
        wantsToPlay = false
        engine.pause()
        if surahWasEnding {
            finishSurah()
            return
        }
        if !isFailed {
            state = .paused
        }
        rememberPosition()
        refreshNowPlaying()
    }

    func resume() {
        guard let item else { return }
        if isFailed {
            if let chapter = pendingQueueChapter {
                advance(to: chapter)
            } else {
                // Try the same surah again from where it was.
                start(item, at: .seconds(position))
            }
            return
        }
        guard !wantsToPlay else { return }
        pausedForPrayer = nil
        if let chapter = pendingQueueChapter {
            advance(to: chapter)
            return
        }
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
        resetAyahRepeat()
        syncPendingAyah()
        updateMarkers()
        engine.seek(to: target)
        if isWaitingForListener || pendingStartAyah != nil {
            // The listener chose a spot: stop waiting (for them or for timings) and play from it.
            cancelListenerWait()
            pendingStartAyah = nil
            if wantsToPlay { engine.play(rate: rate) }
        }
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
        loopAyahs = nil
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

    /// Loops from the start of the first ayah to the end of the last, through `loopRange`.
    /// Nil clears the loop. Without timings, or for ayahs the timings do not have, nothing
    /// changes and it returns false.
    @discardableResult
    func setLoopAyahs(_ range: ClosedRange<Int>?) -> Bool {
        guard let range else {
            setLoopRange(nil)
            return true
        }
        guard let first = ayahTiming(range.lowerBound),
              let last = ayahTiming(range.upperBound),
              last.end > first.start
        else { return false }
        setLoopRange(first.start...last.end)
        guard loopRange != nil else { return false }
        loopAyahs = range
        return true
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
    /// Wins over repeat, play next, play a set and the ayah modes.
    func sleepAtEndOfSurah() {
        cancelSleepTimer()
        sleepsAtEndOfSurah = true
    }

    /// Recite after me: ends the listener's turn early and plays on.
    func continueAfterListener() {
        guard isWaitingForListener else { return }
        finishListenerWait(token: waitToken)
    }

    /// Stops playback, clears the surah and removes the lock screen controls.
    func stop() {
        rememberPosition()
        endSleepFade()
        cancelSleepTimer()
        cancelListenerWait()
        cancelQueue()
        cancelTimingLoad()
        wantsToPlay = false
        wasPlayingBeforeInterruption = false
        engine.stop()
        item = nil
        state = .idle
        position = 0
        duration = 0
        loopRange = nil
        loopAyahs = nil
        resetTimings()
        resetAyahRepeat()
        pendingQueueChapter = nil
        pendingStartAyah = nil
        pausedForPrayer = nil
        resumedFrom = nil
        surahRepeatsDone = 0
        system.updateNowPlaying(nil)
        system.disconnect()
    }

    // MARK: - Pause for prayer

    /// Called by the prayer time signal. Pauses if `modes.pausesForPrayer` is on and something
    /// is playing, and sets `pausedForPrayer` so the UI can offer to resume.
    func prayerTimeArrived(name: String) {
        guard modes.pausesForPrayer, item != nil, wantsToPlay else { return }
        pause()
        pausedForPrayer = name
    }

    /// Hides the prayer pause notice without resuming.
    func clearPrayerPause() {
        pausedForPrayer = nil
    }

    // MARK: - Resume where I stopped

    /// The remembered spot for a reciter and surah, in seconds, if any.
    func savedPosition(reciterID: Int, chapter: Int) -> Double? {
        loadResumeEntries().last { $0.reciterID == reciterID && $0.chapter == chapter }?.seconds
    }

    /// Forgets the remembered spot for the current surah and goes back to its start.
    func startOver() {
        guard let item else { return }
        forgetPosition(of: item)
        resumedFrom = nil
        seek(to: 0)
        lastSavedPosition = 0
    }

    /// True when `seconds` is worth starting from: past the margin and not near the end.
    static func isResumable(_ seconds: Double, duration: Double) -> Bool {
        guard seconds.isFinite, seconds > resumeMargin else { return false }
        guard duration > 0 else { return true }
        return seconds < duration - resumeMargin
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

    // MARK: - Test hooks

    /// Waits for the timings lookup under way, if any.
    func timingsLoadFinished() async {
        if let task = timingTask { await task.value }
    }

    /// Waits for the next surah lookup under way, if any.
    func queueLookupFinished() async {
        if let task = queueTask { await task.value }
    }

    // MARK: - Starting an item

    private func start(_ item: NowPlayingItem, at startPoint: StartPoint) {
        rememberPosition()
        endSleepFade()
        cancelListenerWait()
        cancelQueue()
        cancelTimingLoad()
        engine.stop()
        self.item = item
        position = 0
        duration = item.audio.durationSeconds ?? 0
        loopRange = nil
        loopAyahs = nil
        resetTimings()
        resetAyahRepeat()
        pendingQueueChapter = nil
        pendingStartAyah = nil
        pausedForPrayer = nil
        resumedFrom = nil
        surahRepeatsDone = 0
        lastSavedPosition = 0
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
        loadTimings(for: item)
        switch startPoint {
        case .beginning:
            break
        case .resume(let seconds):
            moveInternally(to: seconds)
            resumedFrom = seconds
            lastSavedPosition = seconds
        case .seconds(let seconds):
            if seconds > 0 { moveInternally(to: seconds) }
        case .ayah(let ayah):
            if timingTask != nil {
                // Starts once the timings arrive (applyTimings).
                pendingStartAyah = ayah
                refreshNowPlaying()
                return
            }
        }
        engine.play(rate: rate)
        refreshNowPlaying()
    }

    private func savedStart(for item: NowPlayingItem) -> StartPoint {
        guard let entry = loadResumeEntries().last(where: {
            $0.reciterID == item.reciter.id && $0.chapter == item.chapter
        }) else { return .beginning }
        let knownDuration = item.audio.durationSeconds ?? entry.duration
        return Self.isResumable(entry.seconds, duration: knownDuration) ? .resume(entry.seconds) : .beginning
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
            guard wantsToPlay, !isWaitingForListener, pendingStartAyah == nil else { return }
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
            updateMarkers()
            handleProgress()
            checkSleepTimer()
        case .ended:
            handleEnd()
        case .failed:
            fail()
        }
    }

    private func handleProgress() {
        let active = wantsToPlay && !isWaitingForListener && pendingStartAyah == nil
        let crossing = active ? ayahCrossing(atSurahEnd: false) : nil
        var moved = crossing?.replayed ?? false
        if !moved, active, let range = loopRange, position >= range.upperBound {
            resetAyahRepeat()
            moveInternally(to: range.lowerBound)
            moved = true
        }
        if !moved {
            syncPendingAyah()
        }
        if let crossing, modes.reciteAfterMe {
            beginListenerWait(for: crossing.timing, then: .play)
        }
        if wantsToPlay, abs(position - lastSavedPosition) >= Self.resumeSaveStep {
            rememberPosition()
        }
    }

    private func handleEnd() {
        if sleepsAtEndOfSurah {
            sleepsAtEndOfSurah = false
            cancelListenerWait()
            finishAtStart()
            return
        }
        if isWaitingForListener {
            afterWait = .endSurah
            return
        }
        if pendingStartAyah == nil, let crossing = ayahCrossing(atSurahEnd: true) {
            if modes.reciteAfterMe {
                beginListenerWait(for: crossing.timing, then: crossing.replayed ? .play : .endSurah)
                return
            }
            if crossing.replayed {
                wantsToPlay = true
                state = .playing
                engine.play(rate: rate)
                refreshNowPlaying()
                return
            }
        }
        completeSurahEnd()
    }

    /// The surah (and any ayah work at its end) is done: sleep, the loop range, then the end action.
    private func completeSurahEnd() {
        if sleepsAtEndOfSurah {
            sleepsAtEndOfSurah = false
            finishAtStart()
            return
        }
        if let range = loopRange {
            restart(at: range.lowerBound)
            return
        }
        guard let item else { return }
        switch modes.surahEnd {
        case .stop:
            finishSurah()
        case .repeatSurah(let times):
            surahRepeatsDone += 1
            if let times, surahRepeatsDone > max(0, times) {
                surahRepeatsDone = 0
                finishSurah()
            } else {
                restart(at: 0)
            }
        case .playNext:
            let next = item.chapter + 1
            if next <= Self.lastChapter {
                advance(to: next)
            } else {
                finishSurah()
            }
        case .playSet(let first, let last):
            let lower = max(1, min(first, last))
            let upper = min(max(first, last), Self.lastChapter)
            let next = item.chapter < lower ? lower : item.chapter + 1
            if next <= upper {
                advance(to: next)
            } else {
                finishSurah()
            }
        }
    }

    private func restart(at seconds: Double) {
        cancelListenerWait()
        resetAyahRepeat()
        moveInternally(to: seconds)
        wantsToPlay = true
        state = .playing
        engine.play(rate: rate)
        refreshNowPlaying()
    }

    /// The surah ended: paused and back at the start, ready to play again.
    private func finishAtStart() {
        cancelListenerWait()
        wantsToPlay = false
        state = .paused
        resetAyahRepeat()
        moveInternally(to: 0)
        refreshNowPlaying()
    }

    /// The surah played to its end, so its remembered spot goes.
    private func finishSurah() {
        if let item { forgetPosition(of: item) }
        finishAtStart()
    }

    private func fail() {
        endSleepFade()
        cancelListenerWait()
        wantsToPlay = false
        engine.pause()
        state = .failed(Self.failureMessage)
        refreshNowPlaying()
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// Sets the position, keeps the ayah tracking in step, and moves the engine.
    private func moveInternally(to seconds: Double) {
        position = max(0, seconds)
        syncPendingAyah()
        updateMarkers()
        engine.seek(to: position)
        refreshNowPlaying()
    }

    // MARK: - Queue

    /// Looks up `chapter` with the same reciter and plays it from the start.
    private func advance(to chapter: Int) {
        guard let current = item else { return }
        guard let resolver = queueResolver else {
            finishSurah()
            return
        }
        forgetPosition(of: current)
        cancelListenerWait()
        cancelQueue()
        pendingQueueChapter = chapter
        pausedForPrayer = nil
        wantsToPlay = true
        state = .loading
        refreshNowPlaying()
        let reciter = current.reciter
        let token = queueToken
        queueTask = Task { @MainActor [weak self] in
            do {
                let next = try await resolver.item(chapter: chapter, reciter: reciter)
                guard let self, self.queueToken == token, !Task.isCancelled else { return }
                self.queueTask = nil
                self.start(next, at: .beginning)
            } catch {
                guard let self, self.queueToken == token, !Task.isCancelled else { return }
                self.queueTask = nil
                // pendingQueueChapter stays, so resume tries this surah again.
                self.fail()
            }
        }
    }

    private func cancelQueue() {
        queueToken += 1
        queueTask?.cancel()
        queueTask = nil
    }

    // MARK: - Timings

    private func loadTimings(for item: NowPlayingItem) {
        cancelTimingLoad()
        guard let provider = timingProvider else { return }
        let reciterID = item.reciter.id
        let chapter = item.chapter
        let token = timingToken
        timingTask = Task { @MainActor [weak self] in
            let loaded = await provider.timings(reciterID: reciterID, chapter: chapter)
            guard let self, self.timingToken == token, !Task.isCancelled else { return }
            self.timingTask = nil
            self.applyTimings(loaded.flatMap {
                ListenTimingLookup.prepared($0, reciterID: reciterID, chapter: chapter)
            })
        }
    }

    private func cancelTimingLoad() {
        timingToken += 1
        timingTask?.cancel()
        timingTask = nil
    }

    private func applyTimings(_ loaded: SurahTimings?) {
        timings = loaded
        timingsAvailable = loaded != nil
        syncPendingAyah()
        updateMarkers()
        guard let ayah = pendingStartAyah else { return }
        pendingStartAyah = nil
        if let ayahStart = ayahTiming(ayah)?.start {
            moveInternally(to: ayahStart)
        }
        if wantsToPlay {
            engine.play(rate: rate)
        }
        refreshNowPlaying()
    }

    private func resetTimings() {
        timings = nil
        timingsAvailable = false
        pendingAyahIndex = nil
        if currentAyah != nil { currentAyah = nil }
        if currentWord != nil { currentWord = nil }
    }

    private func ayahTiming(_ ayah: Int) -> AyahTiming? {
        guard timingsAvailable else { return nil }
        return timings?.ayahs.first { $0.ayah == ayah }
    }

    /// Publishes the ayah and word at `position` by binary search, only when they change.
    private func updateMarkers() {
        var ayah: Int?
        var word: Int?
        if timingsAvailable, let ayahs = timings?.ayahs,
           let index = ListenTimingLookup.ayahIndex(at: position, in: ayahs) {
            ayah = ayahs[index].ayah
            word = ListenTimingLookup.wordPosition(at: position, in: ayahs[index].words)
        }
        if currentAyah != ayah { currentAyah = ayah }
        if currentWord != word { currentWord = word }
    }

    private func syncPendingAyah() {
        guard timingsAvailable, let ayahs = timings?.ayahs else {
            pendingAyahIndex = nil
            return
        }
        pendingAyahIndex = ListenTimingLookup.ayahIndex(at: position, in: ayahs)
    }

    // MARK: - Ayah repeat and recite after me

    /// Handles the end of the ayah that was playing: counts the play and, for ayah repeat,
    /// jumps back to its start. Nil when no ayah ended. At the surah end the last ayah has ended.
    private func ayahCrossing(atSurahEnd: Bool) -> AyahCrossing? {
        guard timingsAvailable, let ayahs = timings?.ayahs,
              let index = pendingAyahIndex, ayahs.indices.contains(index)
        else { return nil }
        let timing = ayahs[index]
        guard atSurahEnd || position >= timing.end else { return nil }
        pendingAyahIndex = nil
        let repeats = max(1, modes.ayahRepeat)
        if repeatingAyah != timing.ayah {
            repeatingAyah = timing.ayah
            ayahPlaysDone = 0
        }
        ayahPlaysDone += 1
        guard repeats > 1, ayahPlaysDone < repeats else {
            resetAyahRepeat()
            return AyahCrossing(timing: timing, replayed: false)
        }
        moveInternally(to: timing.start)
        return AyahCrossing(timing: timing, replayed: true)
    }

    private func resetAyahRepeat() {
        repeatingAyah = nil
        ayahPlaysDone = 0
    }

    /// Goes silent for as long as the ayah lasted (its own length, not scaled by speed).
    private func beginListenerWait(for timing: AyahTiming, then next: AfterWait) {
        waitToken += 1
        let token = waitToken
        afterWait = next
        isWaitingForListener = true
        engine.pause()
        refreshNowPlaying()
        scheduleWait(max(0, timing.end - timing.start)) { [weak self] in
            self?.finishListenerWait(token: token)
        }
    }

    private func finishListenerWait(token: Int) {
        guard token == waitToken, isWaitingForListener else { return }
        isWaitingForListener = false
        let next = afterWait
        afterWait = .play
        switch next {
        case .play:
            guard wantsToPlay else { return }
            state = .playing
            engine.play(rate: rate)
            refreshNowPlaying()
        case .endSurah:
            completeSurahEnd()
        }
    }

    private func cancelListenerWait() {
        guard isWaitingForListener else { return }
        waitToken += 1
        isWaitingForListener = false
        afterWait = .play
    }

    // MARK: - Modes

    private static func loadModes(from defaults: UserDefaults) -> PlayModes {
        guard let data = defaults.data(forKey: modesKey),
              let decoded = try? JSONDecoder().decode(PlayModes.self, from: data)
        else { return PlayModes() }
        return decoded
    }

    private func modesDidChange(from old: PlayModes) {
        if let data = try? JSONEncoder().encode(modes) {
            defaults.set(data, forKey: Self.modesKey)
        }
        if old.surahEnd != modes.surahEnd {
            surahRepeatsDone = 0
        }
        if old.ayahRepeat != modes.ayahRepeat {
            resetAyahRepeat()
        }
        if old.reciteAfterMe, !modes.reciteAfterMe, isWaitingForListener {
            finishListenerWait(token: waitToken)
        }
    }

    // MARK: - Resume store

    private func loadResumeEntries() -> [ListenResumeEntry] {
        guard let data = defaults.data(forKey: Self.resumeKey),
              let entries = try? JSONDecoder().decode([ListenResumeEntry].self, from: data)
        else { return [] }
        return entries
    }

    private func saveResumeEntries(_ entries: [ListenResumeEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.resumeKey)
    }

    /// Saves the current spot, or forgets it when it is too near either end to be worth keeping.
    private func rememberPosition() {
        guard let item else { return }
        lastSavedPosition = position
        let knownDuration = duration > 0 ? duration : (item.audio.durationSeconds ?? 0)
        guard Self.isResumable(position, duration: knownDuration) else {
            forgetPosition(of: item)
            return
        }
        var entries = loadResumeEntries().filter {
            !($0.reciterID == item.reciter.id && $0.chapter == item.chapter)
        }
        entries.append(ListenResumeEntry(
            reciterID: item.reciter.id,
            chapter: item.chapter,
            seconds: position,
            duration: knownDuration
        ))
        if entries.count > Self.resumeLimit {
            entries.removeFirst(entries.count - Self.resumeLimit)
        }
        saveResumeEntries(entries)
    }

    private func forgetPosition(of item: NowPlayingItem) {
        let entries = loadResumeEntries()
        let kept = entries.filter { !($0.reciterID == item.reciter.id && $0.chapter == item.chapter) }
        if kept.count != entries.count {
            saveResumeEntries(kept)
        }
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
        let sounding = state == .playing && !isWaitingForListener
        system.updateNowPlaying(ListenNowPlayingInfo(
            title: item.chapterName,
            artist: item.reciter.name,
            album: ListenNowPlayingInfo.album,
            elapsed: position,
            duration: duration,
            rate: sounding ? rate : 0,
            defaultRate: rate
        ))
    }
}
