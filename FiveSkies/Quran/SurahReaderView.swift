import SwiftUI
import UIKit

/// Reads one sura verse by verse, in the Amiri Quran typeface, exactly as stored.
struct SurahReaderView: View {
    static let textSizeKey = "quranArabicTextSize"
    static let textSizeRange: ClosedRange<Double> = 22...44
    static let defaultTextSize: Double = 30

    let suraNumber: Int
    let initialAyah: Int?

    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var bookmarks: QuranBookmarksStore
    @EnvironmentObject private var lastRead: QuranLastReadStore
    @EnvironmentObject private var translations: TranslationStore

    @AppStorage(SurahReaderView.textSizeKey) private var textSize: Double = SurahReaderView.defaultTextSize

    @State private var selectedAyah: Ayah?
    @State private var showsActions = false
    @State private var showsTextSize = false
    @State private var shareItem: QuranShareItem?
    @State private var shareCardAyah: Ayah?
    @State private var didInitialScroll = false
    @State private var visibleAyahs: Set<Int> = []
    @State private var saveTask: Task<Void, Never>?
    /// Word ranges over the stored ayah strings, lined up with the player's timings (rules W1 to W5).
    @State private var followAlong: SurahFollowAlong?

    var body: some View {
        Group {
            if let data = quran.data, let sura = data.sura(suraNumber) {
                reader(data: data, sura: sura)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .quranSkyBackground()
            }
        }
        .navigationTitle(quran.sura(suraNumber)?.transliteratedName ?? "Quran")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsTextSize = true
                } label: {
                    Text("Aa")
                        .font(.headline.weight(.heavy))
                }
                .accessibilityLabel("Text size")
                .accessibilityIdentifier("readerTextSize")
            }
        }
        .sheet(isPresented: $showsTextSize) {
            ReaderTextSizeSheet(size: $textSize)
                .environmentObject(translations)
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            saveTask?.cancel()
        }
        .task {
            await translations.readerOpened()
        }
    }

    private var dialogTitle: String {
        guard let selectedAyah else { return "Ayah" }
        return "Ayah \(selectedAyah.number)"
    }

    private func clampedTextSize() -> CGFloat {
        CGFloat(min(max(textSize, Self.textSizeRange.lowerBound), Self.textSizeRange.upperBound))
    }

    private func reader(data: QuranData, sura: Sura) -> some View {
        let ayahs = data.ayahs(inSura: sura.number)
        let size = clampedTextSize()
        let basmala = ayahs.first?.basmala
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    header(sura)
                        .padding(.bottom, 4)

                    if let basmala {
                        Text(verbatim: basmala)
                            .font(QuranPalette.arabicFont(size: size))
                            .lineSpacing(size * 0.6)
                            .foregroundStyle(QuranPalette.arabicText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                            .environment(\.layoutDirection, .rightToLeft)
                            .quranSpeechLanguage("ar")
                            .accessibilityIdentifier("basmalaHeader")
                    }

                    ForEach(ayahs, id: \.number) { ayah in
                        ayahButton(ayah, data: data, size: size)
                            .onAppear { ayahAppeared(ayah.number) }
                            .onDisappear { visibleAyahs.remove(ayah.number) }
                    }

                    if let loaded = translations.loaded {
                        TranslationAttributionFooter(
                            summary: loaded.summary,
                            needsRefresh: translations.needsRefresh(loaded.summary)
                        )
                        .padding(.top, 8)
                    } else {
                        Text(translations.isConnected ? "Choose a translation in Aa. Tafsir is coming soon." : "Translations and tafsir are coming soon.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .onAppear {
                scrollToInitialAyah(proxy, count: ayahs.count)
            }
            // A separate watcher, so the reader itself does not redraw on every player update.
            .background(FollowAlongTimingsWatcher(chapter: sura.number, ayahs: ayahs, followAlong: $followAlong))
        }
        .quranSkyBackground()
        .foregroundStyle(.white)
        .confirmationDialog(
            dialogTitle,
            isPresented: $showsActions,
            titleVisibility: .visible,
            presenting: selectedAyah
        ) { ayah in
            if bookmarks.contains(ayah.ref) {
                Button("Remove bookmark") {
                    bookmarks.remove(ayah.ref)
                }
            } else {
                Button("Bookmark") {
                    bookmarks.add(ayah.ref)
                }
            }
            Button("Copy") {
                UIPasteboard.general.string = Self.shareText(for: ayah)
            }
            Button("Share") {
                let text = Self.shareText(for: ayah)
                // Let the dialog finish closing before the share sheet opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    shareItem = QuranShareItem(text: text)
                }
            }
            Button("Share as image") {
                // Let the dialog finish closing before the card sheet opens.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    shareCardAyah = ayah
                }
            }
            Button("Mark as last read") {
                lastRead.update(ayah.ref)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $shareItem) { item in
            QuranActivityView(items: [item.text])
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareCardAyah) { ayah in
            ShareCardView(ayah: ayah, sura: sura)
        }
    }

    // MARK: - Header

    private func header(_ sura: Sura) -> some View {
        VStack(spacing: 6) {
            MoreCaption(text: "Surah \(sura.number) · \(sura.revelation.title)")
            Text(verbatim: sura.arabicName)
                .font(QuranPalette.arabicFont(size: 40))
                .foregroundStyle(QuranPalette.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
                .quranSpeechLanguage("ar")
            Text(verbatim: sura.transliteratedName)
                .font(.title2.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("readerTitle")
            Text(verbatim: "\(sura.englishName) · \(sura.ayahCount) ayahs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .moreGlass(.light, cornerRadius: 30)
    }

    // MARK: - Ayah rows

    private func ayahButton(_ ayah: Ayah, data: QuranData, size: CGFloat) -> some View {
        let isBookmarked = bookmarks.contains(ayah.ref)
        let captions = Self.captions(for: ayah.ref, in: data)
        let translation = translations.text(for: ayah.sura, aya: ayah.number)
        return Button {
            selectedAyah = ayah
            showsActions = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                FollowAlongAyahText(ayah: ayah, followAlong: followAlong, size: size)

                if let translation {
                    AyahTranslationText(text: translation)
                }

                HStack(spacing: 8) {
                    ForEach(captions, id: \.self) { caption in
                        Text(verbatim: caption)
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(QuranPalette.gold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    Spacer(minLength: 4)
                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.footnote)
                            .foregroundStyle(QuranPalette.gold)
                    }
                    AyahNumberMarker(number: ayah.number)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .moreGlass(.dark, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .quranFadeIn()
        .accessibilityLabel(Text(verbatim: Self.ayahAccessibilityLabel(ayah: ayah.number, captions: captions, bookmarked: isBookmarked)))
        .accessibilityValue(Text(verbatim: Self.ayahAccessibilityValue(arabic: ayah.displayText, translation: translation)))
        .accessibilityHint("Shows bookmark, copy and share")
        .accessibilityIdentifier("ayah-\(ayah.number)")
    }

    /// The Arabic as stored, then the translation when one is shown.
    static func ayahAccessibilityValue(arabic: String, translation: String?) -> String {
        guard let translation, !translation.isEmpty else { return arabic }
        return "\(arabic)\nTranslation: \(translation)"
    }

    static func ayahAccessibilityLabel(ayah: Int, captions: [String], bookmarked: Bool) -> String {
        var parts = ["Ayah \(ayah)"]
        parts.append(contentsOf: captions)
        if bookmarked {
            parts.append("Bookmarked")
        }
        return parts.joined(separator: ", ")
    }

    /// "Juz 2", "Page 22" and "Sajda" captions for an ayah, where they apply.
    static func captions(for ref: AyahRef, in data: QuranData) -> [String] {
        var result: [String] = []
        if let juz = data.juzStarting(at: ref) {
            result.append("Juz \(juz)")
        }
        if let page = data.pageStarting(at: ref) {
            result.append("Page \(page)")
        }
        if data.sajda(at: ref) != nil {
            result.append("Sajda")
        }
        return result
    }

    /// The stored Arabic text, a new line, then the reference and source.
    static func shareText(for ayah: Ayah) -> String {
        "\(ayah.text)\nQuran \(ayah.sura):\(ayah.number), text from tanzil.net"
    }

    // MARK: - Scrolling and last read

    private func scrollToInitialAyah(_ proxy: ScrollViewProxy, count: Int) {
        guard !didInitialScroll else { return }
        didInitialScroll = true
        guard let target = initialAyah, target > 1, target <= count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    /// Remembers the top-most ayah once the scroll has rested on it for a moment.
    private func ayahAppeared(_ number: Int) {
        visibleAyahs.insert(number)
        saveTask?.cancel()
        let sura = suraNumber
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let top = visibleAyahs.min() else { return }
            lastRead.update(AyahRef(sura: sura, aya: top))
        }
    }
}

struct QuranShareItem: Identifiable {
    let id = UUID()
    let text: String
}

/// The system share sheet.
struct QuranActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The "Aa" sheet: Arabic text size and the translation choice.
struct ReaderTextSizeSheet: View {
    @Binding var size: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reading")
                .font(.title3.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("textSizeTitle")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Arabic text size")
                        .font(.headline)
                    Spacer()
                    Text(verbatim: "\(Int(size.rounded())) pt")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .accessibilityHidden(true)
                }
                Slider(
                    value: $size,
                    in: SurahReaderView.textSizeRange,
                    step: 1
                ) {
                    Text("Arabic text size")
                } minimumValueLabel: {
                    Text("A")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                } maximumValueLabel: {
                    Text("A")
                        .font(.title2.weight(.bold))
                        .accessibilityHidden(true)
                }
                .accessibilityValue(Text(verbatim: "\(Int(size.rounded())) points"))
                .accessibilityIdentifier("textSizeSlider")
            }

            TranslationSettingsRow()

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MorePalette.ink.ignoresSafeArea())
    }
}

/// The Arabic of one ayah, drawn from the stored string exactly as it is (rule W1).
/// While this surah plays, the current word is drawn in gold, or the whole ayah is marked when
/// it lines up at ayah level only (W3). The highlight is drawing only: no animation (W8, so
/// nothing moves under Reduce Motion) and nothing is announced to VoiceOver.
/// It watches the player itself, so the frequent position updates redraw only visible ayahs.
private struct FollowAlongAyahText: View {
    let ayah: Ayah
    let followAlong: SurahFollowAlong?
    let size: CGFloat

    @EnvironmentObject private var player: ListenPlayer

    var body: some View {
        let highlight = FollowAlongState.highlight(
            readerChapter: ayah.sura,
            playingChapter: player.item?.chapter,
            currentAyah: player.currentAyah,
            currentWord: player.currentWord,
            followAlong: followAlong
        )
        let current = highlight?.ayah == ayah.number ? highlight : nil
        return Text(attributedText(current))
            .font(QuranPalette.arabicFont(size: size))
            .lineSpacing(size * 0.6)
            .foregroundStyle(QuranPalette.arabicText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, size * 0.2)
            .environment(\.layoutDirection, .rightToLeft)
            .quranSpeechLanguage("ar")
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(QuranPalette.gold.opacity(current == nil ? 0 : 0.1))
                    .padding(-6)
            )
            .transaction { $0.animation = nil }
    }

    /// The stored string as an AttributedString, with the playing word coloured.
    /// The ranges come from `SurahFollowAlong` and index this same string; nothing is rebuilt.
    private func attributedText(_ highlight: FollowAlongHighlight?) -> AttributedString {
        let shown = followAlong?.text(forAyah: ayah.number)
        let source = shown?.text ?? ayah.displayText
        var attributed = AttributedString(source)
        guard case let .word(_, range)? = highlight, let shown, shown.text == source else {
            return attributed
        }
        let offsets = shown.scalarOffsets(of: range)
        let scalars = attributed.unicodeScalars
        guard offsets.lowerBound >= 0, offsets.upperBound <= scalars.count, offsets.lowerBound < offsets.upperBound else {
            return attributed
        }
        let lower = scalars.index(scalars.startIndex, offsetBy: offsets.lowerBound)
        let upper = scalars.index(scalars.startIndex, offsetBy: offsets.upperBound)
        attributed[lower..<upper].foregroundColor = QuranPalette.gold
        return attributed
    }
}

/// Rebuilds the follow-along ranges when the player's timings change. Draws nothing.
private struct FollowAlongTimingsWatcher: View {
    let chapter: Int
    let ayahs: [Ayah]
    @Binding var followAlong: SurahFollowAlong?

    @EnvironmentObject private var player: ListenPlayer

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: player.timings, initial: true) { _, timings in
                followAlong = SurahFollowAlong(chapter: chapter, ayahs: ayahs, timings: timings)
                #if DEBUG
                if let timings, timings.chapter == chapter {
                    _ = FollowAlongDebugReport.report(timings: timings, ayahs: ayahs)
                }
                #endif
            }
    }
}
