import SwiftUI

/// Which ayah the reader hides right now: the one whose turn it is in Memorize.
/// Pure, so it can be tested without a player.
enum MemorizeTurn {
    /// UI tests freeze a turn with `-FSMemorizeTurn sura:ayah`.
    static let argument = "-FSMemorizeTurn"

    static func hiddenAyah(
        readerChapter: Int,
        playingChapter: Int?,
        hidesAyahWhileWaiting: Bool,
        isWaitingForListener: Bool,
        currentAyah: Int?
    ) -> Int? {
        guard hidesAyahWhileWaiting, isWaitingForListener, playingChapter == readerChapter else { return nil }
        return currentAyah
    }

    static func frozenAyah(forChapter chapter: Int, arguments: [String] = ProcessInfo.processInfo.arguments) -> Int? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1),
              let ref = ref(from: arguments[index + 1]), ref.sura == chapter
        else { return nil }
        return ref.aya
    }

    /// Reads "sura:ayah".
    static func ref(from key: String) -> AyahRef? {
        let parts = key.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 1, parts[1] >= 1 else { return nil }
        return AyahRef(sura: parts[0], aya: parts[1])
    }
}

/// Watches the player and hands the reader the hidden ayah, so the reader itself does not
/// redraw on every player update.
struct MemorizeTurnWatcher: View {
    let chapter: Int
    @Binding var hiddenAyah: Int?

    @EnvironmentObject private var player: ListenPlayer

    var body: some View {
        let hidden = MemorizeTurn.frozenAyah(forChapter: chapter) ?? MemorizeTurn.hiddenAyah(
            readerChapter: chapter,
            playingChapter: player.item?.chapter,
            hidesAyahWhileWaiting: player.modes.hidesAyahWhileWaiting,
            isWaitingForListener: player.isWaitingForListener,
            currentAyah: player.currentAyah
        )
        return Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: hidden, initial: true) { _, value in
                if hiddenAyah != value {
                    hiddenAyah = value
                }
            }
    }
}

/// Covers an ayah card during the listener's turn. The Arabic underneath is the same text,
/// drawn the same way, only made invisible; nothing about the stored string changes.
struct MemorizeTurnCover: View {
    let ayah: Int
    let isKnown: Bool
    let onPeek: () -> Void
    /// Marks the ayah known, or takes the mark back when it already is.
    let onKnown: () -> Void

    @State private var marks = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2.weight(.bold))
                .foregroundStyle(QuranPalette.gold)
                .accessibilityHidden(true)
            Text("Your turn. Recite ayah \(ayah).")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button {
                    onPeek()
                } label: {
                    Label("Peek", systemImage: "eye")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .moreGlass(.light, cornerRadius: 18)
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("memorizePeek")

                Button {
                    marks += 1
                    onKnown()
                } label: {
                    Label(isKnown ? "Known, tap to undo" : "I know this", systemImage: isKnown ? "checkmark.seal.fill" : "checkmark.seal")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MorePalette.goldGradient))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("memorizeKnown")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color(hex: 0x120B1F, opacity: 0.96)))
        .overlay(shape.strokeBorder(QuranPalette.gold.opacity(0.5), lineWidth: 1))
        .sensoryFeedback(.success, trigger: marks)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memorizeTurn-\(ayah)")
    }
}
