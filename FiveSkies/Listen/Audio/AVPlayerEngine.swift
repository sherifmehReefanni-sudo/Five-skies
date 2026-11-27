import AVFoundation
import Foundation

/// Streams one file at a time with AVPlayer, straight from the URL the API returned (D3).
/// Nothing is cached or copied by this engine.
@MainActor
final class AVPlayerEngine: PlaybackEngine {
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var controlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var fadeTask: Task<Void, Never>?
    /// A seek asked for before the item was ready. Applied once it is ready.
    private var pendingSeek: Double?
    /// A seek under way. Until it lands, progress reports show its target, not the old time,
    /// so the player's ayah tracking never sees a stale position.
    private var seekTarget: Double?
    private var seekGeneration = 0

    init() {
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                self?.reportProgress(seconds)
            }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            let engine = self
            Task { @MainActor in
                engine?.handleControlStatus(status)
            }
        }
    }

    func load(url: URL, expectedDuration: Double?) {
        cancelFade()
        removeItemObservers()
        clearSeeks()
        let item = AVPlayerItem(url: url)
        // Keeps the reciter's pitch when the speed changes.
        item.audioTimePitchAlgorithm = .spectral
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            let engine = self
            Task { @MainActor in
                engine?.handleItemStatus(status, durationSeconds: seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onEvent?(.ended)
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onEvent?(.failed)
            }
        }
        player.replaceCurrentItem(with: item)
    }

    func play(rate: Float) {
        cancelFade()
        player.defaultRate = rate
        player.play()
    }

    func pause() {
        fadeTask?.cancel()
        fadeTask = nil
        player.pause()
        player.volume = 1
    }

    func seek(to seconds: Double) {
        guard let item = player.currentItem else { return }
        let clamped = max(0, seconds)
        guard item.status == .readyToPlay else {
            // A resume spot or play from ayah, asked for while the file is still opening.
            pendingSeek = clamped
            reportProgress(clamped)
            return
        }
        pendingSeek = nil
        seekPlayer(to: clamped)
        reportProgress(clamped)
    }

    private func seekPlayer(to seconds: Double) {
        seekGeneration += 1
        let generation = seekGeneration
        seekTarget = seconds
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            let engine = self
            Task { @MainActor in
                engine?.seekLanded(generation: generation)
            }
        }
    }

    private func seekLanded(generation: Int) {
        guard generation == seekGeneration else { return }
        seekTarget = nil
    }

    private func clearSeeks() {
        pendingSeek = nil
        seekTarget = nil
        seekGeneration += 1
    }

    func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.rate != 0 {
            player.rate = rate
        }
    }

    func fadeOut(over seconds: Double, then completion: @escaping @MainActor @Sendable () -> Void) {
        cancelFade()
        let steps = 30
        let stepNanoseconds = UInt64(max(0.01, seconds / Double(steps)) * 1_000_000_000)
        fadeTask = Task { @MainActor [weak self] in
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepNanoseconds)
                guard !Task.isCancelled, let self else { return }
                self.player.volume = Float(steps - step) / Float(steps)
            }
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        player.volume = 1
    }

    func stop() {
        cancelFade()
        player.pause()
        removeItemObservers()
        clearSeeks()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Reports

    private func currentDuration() -> Double? {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
    }

    private func reportProgress(_ seconds: Double) {
        guard player.currentItem != nil else { return }
        // Until a pending seek is applied, the clock still reads the start of the file.
        let shown = pendingSeek ?? seekTarget ?? seconds
        guard shown.isFinite else { return }
        onEvent?(.progress(position: max(0, shown), duration: currentDuration()))
    }

    private func handleControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard player.currentItem != nil else { return }
        switch status {
        case .waitingToPlayAtSpecifiedRate:
            onEvent?(.buffering(true))
        case .playing:
            onEvent?(.buffering(false))
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, durationSeconds: Double) {
        guard player.currentItem != nil else { return }
        switch status {
        case .readyToPlay:
            if let target = pendingSeek {
                pendingSeek = nil
                seekPlayer(to: target)
            }
            let duration: Double? = (durationSeconds.isFinite && durationSeconds > 0) ? durationSeconds : nil
            onEvent?(.ready(duration: duration))
        case .failed:
            onEvent?(.failed)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func removeItemObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        failObserver = nil
    }
}
