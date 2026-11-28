import SwiftUI
import UIKit

/// Reads one sura verse by verse, in the Amiri Quran typeface, exactly as stored.
struct SurahReaderView: View {
    static let textSizeKey = "quranArabicTextSize"
    static let textSizeRange: ClosedRange<Double> = 22...44
    static let defaultTextSize: Double = 30

    let suraNumber: Int
    let initialAyah: Int?
    /// The Quran tab's listening model, for "Play from this ayah". A plain reference, not observed,
    /// so the reader does not redraw when it changes. Nil hides the play option.
    var listen: QuranListenModel? = nil

    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var bookmarks: QuranBookmarksStore
    @EnvironmentObject private var lastRead: QuranLastReadStore
    @EnvironmentObject private var translations: TranslationStore
    @EnvironmentObject private var navigator: QuranNavigator

    @AppStorage(SurahReaderView.textSizeKey) private var textSize: Double = SurahReaderView.defaultTextSize
    @AppStorage(ReadingPreferences.showsTranslationKey) private var showsTranslation: Bool = ReadingPreferences.defaultShowsTranslation

    /// The ayah whose toolbar is showing (E1.1).
    @State private var toolbarItem: AyahToolbarItem?
    @State private var showsTextSize = false
    @State private var shareItem: QuranShareItem?
    @State private var shareCardAyah: Ayah?
    @State private var didInitialScroll = false
    @State private var visibleAyahs: Set<Int> = []
    @State private var saveTask: Task<Void, Never>?
    /// Word ranges over the stored ayah strings, lined up with the player's timings (rules W1 to W5).
    @State private var followAlong: SurahFollowAlong?
    /// Keeps the ayah being recited in view. Off once the listener drags the list.
    @State private var followsRecitation = true
    /// True while this surah plays with timings, so following can work.
    @State private var isFollowable = false
    @State private var playFromStartsAtBeginning = false
    /// The ayah picked in "Play from this ayah", handed to `ReaderListenWatcher`.
    @State private var playFromRequest: Int?
    /// Memorize: the ayah whose turn it is, hidden until the listener peeks (E2.1).
    @State private var hiddenAyah: Int?
    @State private var peekedAyah: Int?
    @ObservedObject private var progress = MemorizeProgressStore.shared
    /// The ayah whose Words sheet is open (E2.2).
    @State private var wordsAyah: Ayah?
    @State private var wordsProvider: (any AyahWordsProviding)? = AyahWordsProviderFactory.live()

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
                .accessibilityLabel("Reading settings")
                .accessibilityIdentifier("readerTextSize")
            }
        }
        .sheet(isPresented: $showsTextSize) {
            ReadingSettingsSheet()
                .environmentObject(translations)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onDisappear {
            saveTask?.cancel()
        }
        .task {
            await translations.readerOpened()
        }
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

                    surahNavigation(current: sura.number, data: data)
                        .padding(.top, 4)

                    TransliterationAttributionFooter()
                        .padding(.top, 8)
                    if let loaded = translations.loaded, showsTranslation {
                        TranslationAttributionFooter(
                            summary: loaded.summary,
                            needsRefresh: translations.needsRefresh(loaded.summary)
                        )
                        .padding(.top, 8)
                    } else if translations.loaded == nil {
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
            .modifier(ReaderStopsFollowingOnDrag(follows: $followsRecitation))
            .onAppear {
                scrollToInitialAyah(proxy, count: ayahs.count)
            }
            // Separate watchers, so the reader itself does not redraw on every player update.
            .background(FollowAlongTimingsWatcher(chapter: sura.number, ayahs: ayahs, followAlong: $followAlong))
            .background(MemorizeTurnWatcher(chapter: sura.number, hiddenAyah: $hiddenAyah))
            .onChange(of: hiddenAyah) { _, _ in
                peekedAyah = nil
            }
            .background(
                ReaderListenWatcher(
                    chapter: sura.number,
                    chapterName: sura.transliteratedName,
                    ayahCount: ayahs.count,
                    listen: listen,
                    proxy: proxy,
                    follows: $followsRecitation,
                    isFollowable: $isFollowable,
                    playFromStartsAtBeginning: $playFromStartsAtBeginning,
                    playRequest: $playFromRequest
                )
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isFollowable && !followsRecitation {
                ReaderFollowPill {
                    followsRecitation = true
                }
                .padding(.bottom, 6)
            }
        }
        .quranSkyBackground()
        .foregroundStyle(.white)
        .ayahToolbar(item: $toolbarItem) { item in
            let ref = AyahRef(sura: item.sura, aya: item.ayah)
            let ayah = data.ayahs(inSura: item.sura).first { $0.number == item.ayah }
            return AyahToolbar(
                title: AyahToolbarText.title(suraName: sura.transliteratedName, ayah: item.ayah),
                isBookmarked: bookmarks.contains(ref),
                playTitle: AyahToolbarText.playTitle(
                    offersPlayback: listen?.offersPlayback ?? false,
                    startsAtBeginning: playFromStartsAtBeginning
                ),
                actions: AyahToolbarActions(
                    play: { playFromRequest = item.ayah },
                    toggleBookmark: {
                        if bookmarks.contains(ref) {
                            bookmarks.remove(ref)
                        } else {
                            bookmarks.add(ref)
                        }
                    },
                    share: {
                        if let ayah {
                            shareItem = QuranShareItem(text: Self.shareText(for: ayah))
                        }
                    },
                    copy: {
                        if let ayah {
                            UIPasteboard.general.string = Self.shareText(for: ayah)
                        }
                    },
                    shareAsImage: { shareCardAyah = ayah },
                    markLastRead: {
                        lastRead.update(ref)
                        ContinueStore.shared.noteReading(sura: item.sura, ayah: item.ayah, at: Date())
                    },
                    words: { wordsAyah = ayah },
                    removeKnownMark: progress.isKnown(ref) ? { progress.clear(ref) } : nil
                ),
                onClose: {}
            )
        }
        .sheet(item: $shareItem) { item in
            QuranActivityView(items: [item.text])
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareCardAyah) { ayah in
            ShareCardView(ayah: ayah, sura: sura)
        }
        .sheet(item: $wordsAyah) { ayah in
            AyahWordsSheetHost(
                ayah: ayah,
                title: AyahToolbarText.title(suraName: sura.transliteratedName, ayah: ayah.number),
                provider: wordsProvider
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Moving between surahs (E1.2 c)

    private func surahNavigation(current: Int, data: QuranData) -> some View {
        HStack(spacing: 10) {
            if current > 1, let previous = data.sura(current - 1) {
                surahStep(title: "Previous", name: previous.transliteratedName, symbol: "chevron.left",
                          identifier: "readerPreviousSurah") {
                    navigator.open(QuranReaderTarget(sura: current - 1, aya: nil))
                }
            }
            if current < 114, let next = data.sura(current + 1) {
                surahStep(title: "Next surah", name: next.transliteratedName, symbol: "chevron.right",
                          identifier: "readerNextSurah") {
                    navigator.open(QuranReaderTarget(sura: current + 1, aya: nil))
                }
            }
        }
    }

    private func surahStep(title: String, name: String, symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if symbol == "chevron.left" { Image(systemName: symbol) }
                    Text(title)
                    if symbol == "chevron.right" { Image(systemName: symbol) }
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(QuranPalette.gold)
                Text(verbatim: name)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .moreGlass(.dark, cornerRadius: 20)
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(title): \(name)"))
        .accessibilityIdentifier(identifier)
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
            if listen?.offersPlayback == true {
                Button {
                    playFromRequest = 1
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(MorePalette.goldGradient))
                }
                .buttonStyle(PressScaleButtonStyle(pressedScale: 0.95))
                .padding(.top, 8)
                .accessibilityLabel("Play this surah")
                .accessibilityIdentifier("readerHeaderPlay")
            }
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
        let translation = showsTranslation ? translations.text(for: ayah.sura, aya: ayah.number) : nil
        let transliteration = translations.showsTransliteration
            ? translations.transliteration(for: ayah.sura, aya: ayah.number)
            : nil
        // Memorize hides the Arabic with opacity only: same string, same drawing path.
        let isHidden = hiddenAyah == ayah.number && peekedAyah != ayah.number
        let isKnown = progress.isKnown(ayah.ref)
        return Button {
            let tapped = AyahToolbarItem(sura: ayah.sura, ayah: ayah.number)
            toolbarItem = toolbarItem == tapped ? nil : tapped
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                FollowAlongAyahText(ayah: ayah, followAlong: followAlong, size: size)
                    .opacity(isHidden ? 0 : 1)

                if let line = transliteration {
                    AyahTransliterationText(text: line)
                        .opacity(isHidden ? 0 : 1)
                }

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
                    if isKnown {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(QuranPalette.gold)
                            .accessibilityLabel("Known")
                    }
                    if isBookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(.footnote)
                            .foregroundStyle(QuranPalette.gold)
                    }
                    AyahNumberMarker(number: ayah.number)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: isHidden ? 180 : nil, alignment: .topLeading)
            .moreGlass(.dark, cornerRadius: 24)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isHidden)
        .quranFadeIn()
        .accessibilityLabel(Text(verbatim: Self.ayahAccessibilityLabel(ayah: ayah.number, captions: captions, bookmarked: isBookmarked)))
        .accessibilityValue(Text(verbatim: Self.ayahAccessibilityValue(arabic: ayah.displayText, transliteration: transliteration, translation: translation)))
        .accessibilityHint("Shows play, bookmark and share")
        .accessibilityIdentifier("ayah-\(ayah.number)")
        .accessibilityHidden(isHidden)
        .overlay {
            if isHidden {
                MemorizeTurnCover(
                    ayah: ayah.number,
                    isKnown: isKnown,
                    onPeek: { peekedAyah = ayah.number },
                    onKnown: {
                        if progress.isKnown(ayah.ref) {
                            progress.clear(ayah.ref)
                        } else {
                            progress.markKnown(ayah.ref)
                            peekedAyah = ayah.number
                        }
                    }
                )
            }
        }
    }

    /// The Arabic as stored, then the transliteration and the translation when they are shown.
    static func ayahAccessibilityValue(arabic: String, transliteration: String? = nil, translation: String?) -> String {
        var parts = [arabic]
        if let transliteration, !transliteration.isEmpty {
            parts.append("Transliteration: \(transliteration)")
        }
        if let translation, !translation.isEmpty {
            parts.append("Translation: \(translation)")
        }
        return parts.joined(separator: "\n")
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
        // Opened at a chosen ayah: stay there. The Follow pill turns following back on.
        followsRecitation = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo(target, anchor: .top)
        }
        // A far jump in a lazy list can land short while rows above are still sizing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
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
            ContinueStore.shared.noteReading(sura: sura, ayah: top, at: Date())
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
        let highlight = FollowAlongFrozenFrame.highlight(for: ayah, followAlong: followAlong)
            ?? FollowAlongState.highlight(
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

/// The `-FSHighlightWord <sura>:<ayah>:<word>` testing hook: draws that word as the playing word,
/// frozen, with no player and no timings, so a screenshot can show how the highlight renders.
/// It uses the same ranges and the same drawing as real playback. No effect without the argument.
enum FollowAlongFrozenFrame {
    static let argument = "-FSHighlightWord"

    private static let target: (sura: Int, ayah: Int, word: Int)? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else {
            return nil
        }
        let parts = arguments[index + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }()

    static func highlight(for ayah: Ayah, followAlong: SurahFollowAlong?) -> FollowAlongHighlight? {
        guard let target, target.sura == ayah.sura, target.ayah == ayah.number,
              let range = followAlong?.text(forAyah: ayah.number)?.range(ofWord: target.word)
        else { return nil }
        return .word(ayah: ayah.number, range: range)
    }
}

// MARK: - Following the recitation

/// Pure rules for following the recitation in the reader.
enum ReaderFollow {
    /// Where the current ayah sits: its top part in the upper third of the screen.
    static let anchor = UnitPoint(x: 0.5, y: 0.25)

    /// The ayah to scroll to, or nil when the reader should stay where it is: following is
    /// off, another surah (or nothing) is playing, or the ayah is not one of this surah's.
    static func target(follows: Bool, readerChapter: Int, playingChapter: Int?, currentAyah: Int?, ayahCount: Int) -> Int? {
        guard follows, playingChapter == readerChapter, let ayah = currentAyah, ayah >= 1, ayah <= ayahCount else {
            return nil
        }
        return ayah
    }
}

/// Follows the recitation and runs "Play from this ayah". Draws nothing.
/// It watches the player so the reader does not: it acts only when the current ayah, the item
/// or the timings change, not on each of the frequent position updates.
private struct ReaderListenWatcher: View {
    let chapter: Int
    let chapterName: String
    let ayahCount: Int
    let listen: QuranListenModel?
    let proxy: ScrollViewProxy
    @Binding var follows: Bool
    @Binding var isFollowable: Bool
    @Binding var playFromStartsAtBeginning: Bool
    @Binding var playRequest: Int?

    @EnvironmentObject private var player: ListenPlayer
    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        let followable = player.item?.chapter == chapter && player.timingsAvailable
        let startsAtBeginning = listen?.playFromAyahStartsAtBeginning(chapter: chapter, in: player) ?? false
        return Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: player.currentAyah) { _, ayah in
                scroll(to: ayah)
            }
            .onChange(of: follows) { _, isOn in
                if isOn {
                    scroll(to: player.currentAyah)
                }
            }
            .onChange(of: player.item?.chapter) { _, playing in
                // A new start of this surah follows again.
                if playing == chapter, !follows {
                    follows = true
                }
            }
            .onChange(of: followable, initial: true) { _, value in
                isFollowable = value
            }
            .onChange(of: startsAtBeginning, initial: true) { _, value in
                playFromStartsAtBeginning = value
            }
            .onChange(of: playRequest) { _, ayah in
                guard let ayah else { return }
                playRequest = nil
                guard let listen else { return }
                follows = true
                listen.play(chapter: chapter, name: chapterName, fromAyah: ayah, on: player)
            }
    }

    /// Scrolls to the ayah being recited. No animation under Reduce Motion (and in screenshot mode).
    private func scroll(to ayah: Int?) {
        guard let target = ReaderFollow.target(
            follows: follows,
            readerChapter: chapter,
            playingChapter: player.item?.chapter,
            currentAyah: ayah,
            ayahCount: ayahCount
        ) else { return }
        if motionEnabled {
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(target, anchor: ReaderFollow.anchor)
            }
        } else {
            proxy.scrollTo(target, anchor: ReaderFollow.anchor)
        }
    }
}

/// Turns following off as soon as the listener drags the list.
/// The reader's own scrolling does not count; only the listener's finger does.
private struct ReaderStopsFollowingOnDrag: ViewModifier {
    @Binding var follows: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if case .interacting = phase, follows {
                    follows = false
                }
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { _ in
                    if follows {
                        follows = false
                    }
                }
            )
        }
    }
}

/// The small "Follow" pill above the play bar, shown after the listener scrolled away.
private struct ReaderFollowPill: View {
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            Label("Follow", systemImage: "waveform")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Capsule().fill(MorePalette.goldGradient))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Follow the recitation")
        .accessibilityHint("Scrolls to the ayah being recited and keeps it in view")
        .accessibilityIdentifier("readerFollow")
    }
}

/// Hands the Words sheet a way to pause the recitation, without the reader observing the player.
private struct AyahWordsSheetHost: View {
    let ayah: Ayah
    let title: String
    let provider: (any AyahWordsProviding)?

    @EnvironmentObject private var player: ListenPlayer

    var body: some View {
        AyahWordsSheet(
            ayah: ayah,
            storedText: ayah.displayText,
            title: title,
            provider: provider,
            pauseRecitation: { player.pause() }
        )
    }
}
