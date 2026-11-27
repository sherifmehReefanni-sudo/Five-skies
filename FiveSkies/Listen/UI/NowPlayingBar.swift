import SwiftUI

/// The bar pinned above the tab bar while something is loaded in the player.
/// Tap it to open the full player. The credit line is always on it (D9).
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
                        Text(verbatim: item.chapterName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(verbatim: item.credit)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Now playing, \(item.chapterName), \(item.credit)"))
            .accessibilityHint("Opens the player")
            .accessibilityIdentifier("nowPlayingOpen")

            ListenPlayPauseButton(size: 44, identifier: "nowPlayingPlayPause")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            progressLine
        }
        .moreGlass(.dark, cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nowPlayingBar")
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
