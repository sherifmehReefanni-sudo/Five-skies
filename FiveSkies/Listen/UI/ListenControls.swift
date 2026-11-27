import SwiftUI

/// The gold play and pause button, used on the now playing bar and in the player sheet.
/// After a failure it becomes Try again and starts the same item over.
struct ListenPlayPauseButton: View {
    @EnvironmentObject private var player: ListenPlayer

    let size: CGFloat
    let identifier: String

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            if isFailed, let item = player.item {
                player.play(item)
            } else {
                player.togglePlayPause()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(MorePalette.goldGradient)
                    .shadow(color: MorePalette.gold.opacity(0.45), radius: size * 0.18)
                if player.state == .loading {
                    ProgressView()
                        .tint(MorePalette.ink)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.38, weight: .heavy))
                        .foregroundStyle(MorePalette.ink)
                        .offset(x: symbol == "play.fill" ? size * 0.03 : 0)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.92))
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(player.state == .loading ? "Loading" : ""))
        .accessibilityIdentifier(identifier)
    }

    private var isFailed: Bool {
        if case .failed = player.state {
            return true
        }
        return false
    }

    private var symbol: String {
        if isFailed {
            return "arrow.clockwise"
        }
        return player.state == .playing ? "pause.fill" : "play.fill"
    }

    private var label: String {
        if isFailed {
            return "Try again"
        }
        return player.state == .playing || player.state == .loading ? "Pause" : "Play"
    }
}

/// A headphones glyph in a gold disc with soft rings that ripple while audio plays
/// and ambient motion is on. Still otherwise.
struct ListenArtwork: View {
    let isPlaying: Bool
    let size: CGFloat

    @Environment(\.ambientMotionEnabled) private var ambientMotion

    var body: some View {
        let animates = ambientMotion && isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
            let time = animates ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let wave = animates
                        ? MotionWave.fraction(time / 2.4 + Double(index) / 3)
                        : 0.25 + 0.25 * Double(index)
                    Circle()
                        .strokeBorder(MorePalette.gold.opacity(0.55 * (1 - wave)), lineWidth: max(1, size * 0.02))
                        .scaleEffect(0.58 + 0.42 * CGFloat(wave))
                }
                Circle()
                    .fill(MorePalette.goldGradient)
                    .frame(width: size * 0.58, height: size * 0.58)
                    .shadow(color: MorePalette.gold.opacity(0.5), radius: size * 0.16)
                Image(systemName: "headphones")
                    .font(.system(size: size * 0.26, weight: .heavy))
                    .foregroundStyle(MorePalette.ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Three small bars on the surah that is playing. They move only while it plays and
/// ambient motion is on; paused, they stand still.
struct ListenPlayingIndicator: View {
    let isPlaying: Bool

    @Environment(\.ambientMotionEnabled) private var ambientMotion

    private static let restingHeights: [Double] = [0.55, 0.95, 0.7]

    var body: some View {
        let animates = ambientMotion && isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let height = animates
                        ? 0.3 + 0.7 * MotionWave.breath(time, period: 0.9, offset: Double(index) * 0.33)
                        : Self.restingHeights[index]
                    Capsule()
                        .fill(MorePalette.gold)
                        .frame(width: 4, height: 18 * CGFloat(height))
                }
            }
            .frame(width: 20, height: 18, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}
