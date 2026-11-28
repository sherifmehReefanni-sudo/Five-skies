import SwiftUI

/// The bar pinned at the bottom of the Quran tab and the reader while something is loaded
/// in the player. Tap it to open the full player. The credit line is always on it (D9).
struct NowPlayingBar: View {
    @EnvironmentObject private var player: ListenPlayer

    let item: NowPlayingItem
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ListenArtwork(isPlaying: player.state == .playing, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(verbatim: item.chapterName)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if player.isWaitingForListener {
                                ListenYourTurnBadge(identifier: "nowPlayingYourTurn")
                            }
                        }
                        // The reciter credit always stays in view (D9); the meaning line joins it while it is read.
                        Text(verbatim: item.credit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let meaning = player.speakingMeaning {
                            Text(verbatim: ListenMeaningText.label(for: meaning))
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(MorePalette.gold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityIdentifier("nowPlayingMeaning")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: accessibilityText))
            .accessibilityHint("Shows the playing ayah, or the player when you are already there")
            .accessibilityIdentifier("nowPlayingOpen")

            ListenPlayPauseButton(size: 44, identifier: "nowPlayingPlayPause")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            progressLine
        }
        // A solid frosted backing first, so rows scrolling underneath never show through the text.
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThickMaterial)
                .environment(\.colorScheme, .dark)
        )
        .moreGlass(.dark, cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nowPlayingBar")
    }

    private var accessibilityText: String {
        var parts = ["Now playing", item.chapterName]
        if player.isWaitingForListener {
            parts.append(ListenPlayModeText.yourTurn)
        }
        parts.append(item.credit)
        return parts.joined(separator: ", ")
    }

    /// A thin gold line along the bottom edge showing how far into the surah playback is.
    private var progressLine: some View {
        GeometryReader { proxy in
            let fraction = player.duration > 0 ? min(1, max(0, player.position / player.duration)) : 0
            Capsule()
                .fill(MorePalette.gold)
                .frame(width: proxy.size.width * CGFloat(fraction), height: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
