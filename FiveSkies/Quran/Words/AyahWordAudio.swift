import AVFoundation
import Foundation

/// Plays one word recording at a time for the Words sheet. Streams straight from the URL the API
/// gave; nothing is cached or copied. Independent of `ListenPlayer`: the only link is the optional
/// `pauseRecitation` closure, called before a word starts so the two never play together.
@MainActor
final class AyahWordAudio: ObservableObject {
    /// The word playing now, or nil.
    @Published private(set) var playingPosition: Int?

    private let pauseRecitation: (() -> Void)?
    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?

    init(pauseRecitation: (() -> Void)? = nil) {
        self.pauseRecitation = pauseRecitation
        player.actionAtItemEnd = .pause
    }

    /// Plays the word, or stops it when it is the one already playing.
    func toggle(position: Int, url: URL) {
        if playingPosition == position {
            stop()
        } else {
            play(position: position, url: url)
        }
    }

    func play(position: Int, url: URL) {
        stop()
        pauseRecitation?()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)

        let item = AVPlayerItem(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finished(item)
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finished(item)
            }
        }
        player.replaceCurrentItem(with: item)
        playingPosition = position
        player.play()
    }

    /// Stops and lets go of the current word. Called when the sheet closes.
    func stop() {
        player.pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)
        playingPosition = nil
    }

    private func finished(_ item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        stop()
    }

    private func removeObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failObserver {
            NotificationCenter.default.removeObserver(failObserver)
        }
        endObserver = nil
        failObserver = nil
    }
}
