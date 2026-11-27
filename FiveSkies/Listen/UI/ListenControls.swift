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

/// "Your turn" while Recite after me waits for the listener.
struct ListenYourTurnBadge: View {
    let identifier: String

    var body: some View {
        Text(ListenPlayModeText.yourTurn)
            .font(.caption.weight(.heavy))
            .foregroundStyle(MorePalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(MorePalette.goldGradient))
            .fixedSize()
            .accessibilityIdentifier(identifier)
    }
}

/// Shown when playback paused because a prayer time came: "Paused for Asr. Resume?"
struct ListenPrayerPauseBanner: View {
    @EnvironmentObject private var player: ListenPlayer

    let prayer: String
    let identifier: String

    @State private var taps = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MorePalette.gold)
                .accessibilityHidden(true)
            Text(verbatim: ListenPlayModeText.prayerPause(prayer))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                taps += 1
                player.resume()
            } label: {
                Text("Resume")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(MorePalette.goldGradient))
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityHint("Plays the surah again from where it paused")
            .accessibilityIdentifier("\(identifier)Resume")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThickMaterial)
                .environment(\.colorScheme, .dark)
        )
        .moreGlass(.dark, cornerRadius: 18)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
