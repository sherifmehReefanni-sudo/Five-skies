import Foundation

/// What an engine reports back to `ListenPlayer`. Always delivered on the main actor.
enum PlaybackEngineEvent: Equatable, Sendable {
    /// The file opened. The duration is given when the engine knows it.
    case ready(duration: Double?)
    /// True while the engine waits for data before it can play, false once sound is playing.
    case buffering(Bool)
    /// The current position, about four times a second while playing and after every seek.
    case progress(position: Double, duration: Double?)
    /// The file played to its end. The engine is paused at the end.
    case ended
    /// The file could not be opened or stopped playing because of an error.
    case failed
}

/// The sound side of the player, so `ListenPlayer` can be tested without audio.
/// `AVPlayerEngine` streams from the Quran Foundation host; `SimulatedEngine` only moves time.
@MainActor
protocol PlaybackEngine: AnyObject {
    var onEvent: (@MainActor (PlaybackEngineEvent) -> Void)? { get set }

    /// Opens a new file and replaces any current one. Does not start playing.
    func load(url: URL, expectedDuration: Double?)
    func play(rate: Float)
    func pause()
    func seek(to seconds: Double)
    /// Changes the speed. Takes effect at once while playing, otherwise at the next `play`.
    func setRate(_ rate: Float)
    /// Lowers the volume to silence over `seconds`, then calls `completion`.
    /// The engine does not pause by itself; the caller pauses in the completion.
    func fadeOut(over seconds: Double, then completion: @escaping @MainActor @Sendable () -> Void)
    /// Stops a fade that is under way and restores full volume.
    func cancelFade()
    /// Stops and releases the current file.
    func stop()
}
