import AVFoundation
import Foundation
import MediaPlayer

/// What the lock screen and Control Center show for the current recitation.
struct ListenNowPlayingInfo: Equatable, Sendable {
    static let album = "Quran Foundation"

    /// The surah name.
    let title: String
    /// The reciter name exactly as the API gives it (D9).
    let artist: String
    let album: String
    let elapsed: Double
    /// Zero when not known yet.
    let duration: Double
    /// Zero while paused or loading, so the lock screen clock stops.
    let rate: Float
    let defaultRate: Float
}

/// The system side of playback: the audio session, the lock screen and the remote commands.
/// `LiveListenSystem` talks to iOS; `QuietListenSystem` does nothing (tests and `-FSFakeListen`).
@MainActor
protocol ListenSystemHooks: AnyObject {
    /// Sets the `.playback` category and activates the session. False if iOS refused.
    func activateSession() -> Bool
    /// Adds the remote command targets and the interruption and route observers. Safe to call again.
    func connect(to player: ListenPlayer)
    /// Removes the targets and observers, clears the lock screen and releases the session.
    func disconnect()
    func updateNowPlaying(_ info: ListenNowPlayingInfo?)
}

/// Does nothing. Used in unit tests and under `-FSFakeListen`.
@MainActor
final class QuietListenSystem: ListenSystemHooks {
    func activateSession() -> Bool { true }
    func connect(to player: ListenPlayer) {}
    func disconnect() {}
    func updateNowPlaying(_ info: ListenNowPlayingInfo?) {}
}

/// The real audio session, MPNowPlayingInfoCenter and MPRemoteCommandCenter.
@MainActor
final class LiveListenSystem: ListenSystemHooks {
    static let skipInterval: Double = 15

    private enum RemoteAction: Sendable {
        case play
        case pause
        case toggle
        case skip(Double)
        case position(Double)
    }

    private weak var player: ListenPlayer?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var observers: [NSObjectProtocol] = []
    private var isConnected = false

    func activateSession() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    func connect(to player: ListenPlayer) {
        self.player = player
        guard !isConnected else { return }
        isConnected = true
        addRemoteCommands()
        addSessionObservers()
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets = []
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func updateNowPlaying(_ info: ListenNowPlayingInfo?) {
        guard let info else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyAlbumTitle: info.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: Double(info.rate),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(info.defaultRate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if info.duration > 0 {
            values[MPMediaItemPropertyPlaybackDuration] = info.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = values
    }

    // MARK: - Remote commands

    private func addRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand, .play)
        add(center.pauseCommand, .pause)
        add(center.togglePlayPauseCommand, .toggle)

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        add(center.skipForwardCommand, .skip(Self.skipInterval))
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        add(center.skipBackwardCommand, .skip(-Self.skipInterval))

        let positionCommand = center.changePlaybackPositionCommand
        positionCommand.isEnabled = true
        let positionTarget = positionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let seconds = event.positionTime
            let system = self
            Task { @MainActor in
                system?.perform(.position(seconds))
            }
            return .success
        }
        targets.append((positionCommand, positionTarget))
    }

    private func add(_ command: MPRemoteCommand, _ action: RemoteAction) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            let system = self
            Task { @MainActor in
                system?.perform(action)
            }
            return .success
        }
        targets.append((command, target))
    }

    private func perform(_ action: RemoteAction) {
        guard let player else { return }
        switch action {
        case .play:
            player.resume()
        case .pause:
            player.pause()
        case .toggle:
            player.togglePlayPause()
        case .skip(let seconds):
            player.skip(by: seconds)
        case .position(let seconds):
            player.seek(to: seconds)
        }
    }

    // MARK: - Interruptions and route changes

    private func addSessionObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        })
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            player?.interruptionBegan()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            player?.interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable
        else { return }
        player?.outputDeviceRemoved()
    }
}
