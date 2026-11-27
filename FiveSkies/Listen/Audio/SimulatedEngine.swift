import Foundation

/// A silent engine: no network, no audio, time only moves forward.
/// Unit tests move time with `tick(by:)`. With `autoAdvances` (used under `-FSFakeListen`)
/// it ticks itself four times a second while playing, so screenshots show a moving player.
/// It never fades: `fadeOut` completes at once.
@MainActor
final class SimulatedEngine: PlaybackEngine {
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)?

    /// When true, the next `load` reports a failure instead of opening.
    var failsOnLoad = false

    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var rate: Float = 1
    private(set) var loadCount = 0
    private(set) var loadedURL: URL?
    private(set) var fadeCount = 0

    private let defaultDuration: Double
    private let autoAdvances: Bool
    private var autoTask: Task<Void, Never>?

    init(defaultDuration: Double = 300, autoAdvances: Bool = false) {
        self.defaultDuration = defaultDuration
        self.autoAdvances = autoAdvances
    }

    func load(url: URL, expectedDuration: Double?) {
        stopAutoTicks()
        loadCount += 1
        isPlaying = false
        position = 0
        if failsOnLoad {
            loadedURL = nil
            duration = 0
            onEvent?(.failed)
            return
        }
        loadedURL = url
        if let expectedDuration, expectedDuration > 0 {
            duration = expectedDuration
        } else {
            duration = defaultDuration
        }
        onEvent?(.ready(duration: duration))
    }

    func play(rate: Float) {
        guard loadedURL != nil else { return }
        self.rate = rate
        isPlaying = true
        onEvent?(.buffering(false))
        startAutoTicks()
    }

    func pause() {
        isPlaying = false
        stopAutoTicks()
    }

    func seek(to seconds: Double) {
        guard loadedURL != nil else { return }
        position = min(max(0, seconds), duration)
        onEvent?(.progress(position: position, duration: duration))
    }

    func setRate(_ rate: Float) {
        self.rate = rate
    }

    func fadeOut(over seconds: Double, then completion: @escaping @MainActor @Sendable () -> Void) {
        fadeCount += 1
        completion()
    }

    func cancelFade() {}

    func stop() {
        stopAutoTicks()
        isPlaying = false
        loadedURL = nil
        position = 0
        duration = 0
    }

    /// Moves time forward by `seconds` of wall time (scaled by the speed) while playing.
    func tick(by seconds: Double) {
        guard isPlaying, loadedURL != nil else { return }
        position = min(duration, position + seconds * Double(rate))
        onEvent?(.progress(position: position, duration: duration))
        if position >= duration {
            isPlaying = false
            stopAutoTicks()
            onEvent?(.ended)
        }
    }

    /// Reports a failure in the middle of playback, as a dropped connection would.
    func simulateFailure() {
        isPlaying = false
        stopAutoTicks()
        onEvent?(.failed)
    }

    private func startAutoTicks() {
        guard autoAdvances, autoTask == nil else { return }
        autoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick(by: 0.25)
            }
        }
    }

    private func stopAutoTicks() {
        autoTask?.cancel()
        autoTask = nil
    }
}
