import SwiftUI

/// Duas from the Quran (docs/LEARN_LISTEN_PLAN.md section 6; keys chosen by FABLE, Nov 28, 2026).
/// A manifest of verse keys and plain English titles only. The Arabic is the bundled Tanzil text
/// and the meaning is the user's chosen translation, always the whole ayah. On the scholar sheet
/// (docs/SCHOLAR_REVIEW.md, section C) before outside testers.
enum QuranDuas {
    struct Entry: Identifiable, Equatable, Sendable {
        let ref: AyahRef
        let title: String
        var id: AyahRef { ref }
    }

    static let entries: [Entry] = [
        Entry(ref: AyahRef(sura: 28, aya: 24), title: "For provision"),
        Entry(ref: AyahRef(sura: 3, aya: 173), title: "Relying on Allah"),
        Entry(ref: AyahRef(sura: 2, aya: 201), title: "Good in this life and the next"),
        Entry(ref: AyahRef(sura: 25, aya: 74), title: "For spouse and children"),
        Entry(ref: AyahRef(sura: 17, aya: 24), title: "For parents"),
    ]

    static let intro = "Whole ayahs from the Quran. The meaning is from your chosen translation."
}

struct QuranDuasView: View {
    let data: QuranData
    let onOpen: (QuranReaderTarget) -> Void

    @EnvironmentObject private var translations: TranslationStore
    @ScaledMetric(relativeTo: .title) private var arabicSize: CGFloat = 26

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Duas from the Quran", identifier: "quranDuasTitle")
                Text(QuranDuas.intro)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                ForEach(Array(QuranDuas.entries.enumerated()), id: \.element.id) { index, entry in
                    if let ayah = data.ayah(entry.ref), let sura = data.sura(entry.ref.sura) {
                        card(entry: entry, ayah: ayah, sura: sura, index: index)
                    }
                }

                if let loaded = translations.loaded {
                    TranslationAttributionFooter(summary: loaded.summary, needsRefresh: translations.needsRefresh(loaded.summary))
                        .padding(.top, 4)
                } else {
                    Text(translations.isConnected ? "Choose a translation in Aa in the Quran tab to see the meaning." : "Translations are coming soon.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .accessibilityIdentifier("quranDuasNoTranslation")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("quranDuas")
    }

    private func card(entry: QuranDuas.Entry, ayah: Ayah, sura: Sura, index: Int) -> some View {
        let meaning = translations.text(for: entry.ref.sura, aya: entry.ref.aya)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title)
                    .font(.headline.weight(.heavy))
                Spacer(minLength: 8)
                Text(verbatim: "\(sura.transliteratedName) \(entry.ref.sura):\(entry.ref.aya)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(QuranPalette.gold)
            }

            // The whole ayah, exactly as stored.
            Text(verbatim: ayah.displayText)
                .font(QuranPalette.arabicFont(size: arabicSize))
                .lineSpacing(arabicSize * 0.5)
                .foregroundStyle(QuranPalette.arabicText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, .rightToLeft)
                .quranSpeechLanguage("ar")

            if let meaning {
                AyahTranslationText(text: meaning)
            }

            Button {
                onOpen(QuranReaderTarget(sura: entry.ref.sura, aya: entry.ref.aya))
            } label: {
                Label("Open in the Quran", systemImage: "book")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .moreGlass(.light, cornerRadius: 18)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("quranDuaOpen-\(index)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quranDua-\(index)")
    }
}
