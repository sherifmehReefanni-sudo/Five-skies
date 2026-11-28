import SwiftUI

/// Where the reader should open: a sura, and optionally an ayah to scroll to.
struct QuranReaderTarget: Hashable {
    let sura: Int
    let aya: Int?
}

enum QuranListMode: String, CaseIterable, Identifiable {
    case surahs
    case juz
    case bookmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .surahs: return "Surahs"
        case .juz: return "Juz"
        case .bookmarks: return "Bookmarks"
        }
    }
}

/// The Quran tab, reader and player in one place: the chosen reciter, continue reading, then
/// the sura, juz and bookmark lists, with a play button on each sura and a play bar at the
/// bottom here and in the reader. Reading silently works with nothing playing.
struct QuranTabView: View {
    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var navigator: QuranNavigator
    @StateObject private var bookmarks = QuranBookmarksStore()
    @StateObject private var lastRead = QuranLastReadStore()
    @StateObject private var listen: QuranListenModel

    @State private var path: [QuranReaderTarget] = []
    @State private var mode: QuranListMode = .surahs
    @State private var query = ""
    @State private var showsReciters = false
    @State private var showsPlayer = false
    @State private var showsGoTo = false
    @State private var goToTarget: QuranReaderTarget?

    init() {
        _listen = StateObject(wrappedValue: QuranListenModel(catalog: ListenCatalogFactory.live()))
    }

    init(catalog: any ListenCatalog, defaults: UserDefaults = .standard) {
        _listen = StateObject(wrappedValue: QuranListenModel(catalog: catalog, defaults: defaults))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    QuranPlayBar(model: listen, readerSura: nil, readerSuraName: nil, onOpenPlayer: openPlayer)
                }
                .navigationTitle("Quran")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if case .loaded = quran.state {
                            Button {
                                showsGoTo = true
                            } label: {
                                Label("Go to", systemImage: "arrow.right.circle")
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline.weight(.heavy))
                            }
                            .accessibilityHint("Jump to a surah, an ayah such as 2:255, a page or a juz")
                            .accessibilityIdentifier("quranGoTo")
                        }
                    }
                }
                .sheet(isPresented: $showsGoTo, onDismiss: {
                    if let target = goToTarget {
                        goToTarget = nil
                        path.append(target)
                    }
                }) {
                    if case .loaded(let data) = quran.state {
                        QuranGoToSheet(data: data) { target in
                            goToTarget = target
                            showsGoTo = false
                        }
                        .presentationDetents([.large])
                    }
                }
                .navigationDestination(for: QuranReaderTarget.self) { target in
                    // Passed as a plain reference, so the reader does not redraw when the model changes.
                    SurahReaderView(suraNumber: target.sura, initialAyah: target.aya, listen: listen)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            QuranPlayBar(
                                model: listen,
                                readerSura: target.sura,
                                readerSuraName: quran.sura(target.sura)?.transliteratedName,
                                onOpenPlayer: openPlayer
                            )
                        }
                }
        }
        .environmentObject(bookmarks)
        .environmentObject(lastRead)
        .onChange(of: navigator.pending, initial: true) { _, target in
            // Continue card, the now playing bar and Go to land here: show that ayah.
            guard let target else { return }
            path = [target]
            navigator.pending = nil
        }
        .modifier(QuranListenHost(model: listen, showsReciters: $showsReciters, showsPlayer: $showsPlayer))
    }

    private func openPlayer() {
        showsPlayer = true
    }

    @ViewBuilder
    private var content: some View {
        switch quran.state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading the Quran")
                    .font(.headline)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .quranSkyBackground()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quranLoading")
        case .failed(let message):
            VStack(spacing: 8) {
                Text("The Quran could not be opened")
                    .font(.headline.weight(.heavy))
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .quranSkyBackground()
            .accessibilityIdentifier("quranFailed")
        case .loaded(let data):
            list(data)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search surahs"
                )
        }
    }

    private func list(_ data: QuranData) -> some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return List {
            if !searching {
                QuranReciterRow(model: listen) {
                    showsReciters = true
                }
                .quranListRow()
            }

            if !searching, let position = lastRead.position, let sura = data.sura(position.sura) {
                continueCard(sura: sura, position: position)
                    .quranListRow()
            }

            if !searching {
                Picker("List", selection: $mode) {
                    ForEach(QuranListMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("quranListMode")
                .quranListRow()
            }

            if searching || mode == .surahs {
                suraRows(QuranSearch.filter(data.suras, query: query))
            } else if mode == .juz {
                juzRows(data)
            } else {
                bookmarkRows(data)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .quranSkyBackground()
        .foregroundStyle(.white)
    }

    // MARK: - Continue reading

    private func continueCard(sura: Sura, position: AyahRef) -> some View {
        Button {
            path.append(QuranReaderTarget(sura: position.sura, aya: position.aya))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    MoreCaption(text: "Continue reading")
                    Text(verbatim: sura.transliteratedName)
                        .font(.title3.weight(.heavy))
                    Text(verbatim: "Ayah \(position.aya) of \(sura.ayahCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                Spacer(minLength: 8)
                Text(verbatim: sura.arabicName)
                    .font(QuranPalette.arabicFont(size: 26))
                    .foregroundStyle(QuranPalette.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .quranSpeechLanguage("ar")
                Image(systemName: "chevron.right")
                    .font(.body.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .moreGlass(.dark, cornerRadius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(verbatim: "Continue reading, \(sura.transliteratedName), ayah \(position.aya)"))
        .accessibilityIdentifier("continueReading")
    }

    // MARK: - Surahs

    @ViewBuilder
    private func suraRows(_ suras: [Sura]) -> some View {
        if suras.isEmpty {
            Text("No surahs match your search.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .quranListRow()
        }
        let offersPlayback = listen.offersPlayback
        ForEach(suras) { sura in
            Button {
                path.append(QuranReaderTarget(sura: sura.number, aya: nil))
            } label: {
                SuraRowLabel(sura: sura, reservesPlayButton: offersPlayback)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text(verbatim: Self.suraAccessibilityLabel(sura)))
            .accessibilityHint("Opens the reader")
            .accessibilityIdentifier("suraRow-\(sura.number)")
            .overlay(alignment: .trailing) {
                if offersPlayback {
                    QuranSurahPlayButton(model: listen, sura: sura)
                        .padding(.trailing, 14)
                }
            }
            .quranListRow()
        }
    }

    static func suraAccessibilityLabel(_ sura: Sura) -> String {
        "\(sura.number), \(sura.transliteratedName), \(sura.englishName), \(sura.ayahCount) ayahs"
    }

    // MARK: - Juz

    @ViewBuilder
    private func juzRows(_ data: QuranData) -> some View {
        ForEach(Array(data.juzStarts.enumerated()), id: \.offset) { offset, ref in
            let juz = offset + 1
            let suraName = data.sura(ref.sura)?.transliteratedName ?? "Surah \(ref.sura)"
            Button {
                path.append(QuranReaderTarget(sura: ref.sura, aya: ref.aya))
            } label: {
                PlainListCard(
                    title: "Juz \(juz)",
                    detail: "Starts at \(suraName), ayah \(ref.aya)",
                    symbol: nil
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text(verbatim: "Juz \(juz), starts at \(suraName), ayah \(ref.aya)"))
            .accessibilityIdentifier("juzRow-\(juz)")
            .quranListRow()
        }
    }

    // MARK: - Bookmarks

    @ViewBuilder
    private func bookmarkRows(_ data: QuranData) -> some View {
        if bookmarks.bookmarks.isEmpty {
            Text("No bookmarks yet. Tap an ayah in the reader to save it here.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
                .quranListRow()
        }
        ForEach(bookmarks.bookmarks, id: \.self) { ref in
            let suraName = data.sura(ref.sura)?.transliteratedName ?? "Surah \(ref.sura)"
            Button {
                path.append(QuranReaderTarget(sura: ref.sura, aya: ref.aya))
            } label: {
                PlainListCard(
                    title: suraName,
                    detail: "Ayah \(ref.aya)",
                    symbol: "bookmark.fill"
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text(verbatim: "\(suraName), ayah \(ref.aya)"))
            .accessibilityIdentifier("bookmarkRow-\(ref.sura)-\(ref.aya)")
            .quranListRow()
        }
        .onDelete { offsets in
            bookmarks.remove(atOffsets: offsets)
        }
    }
}

/// One sura in the list: number badge, names and counts, Arabic name on the right.
/// Leaves room on the right for the play button drawn over the row.
private struct SuraRowLabel: View {
    let sura: Sura
    let reservesPlayButton: Bool

    var body: some View {
        HStack(spacing: 12) {
            SuraNumberBadge(number: sura.number)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sura.transliteratedName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: "\(sura.englishName) · \(sura.revelation.title) · \(sura.ayahCount) ayahs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(verbatim: sura.arabicName)
                .font(QuranPalette.arabicFont(size: 24))
                .foregroundStyle(QuranPalette.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .quranSpeechLanguage("ar")
            if reservesPlayButton {
                Color.clear
                    .frame(width: QuranSurahPlayButton.size, height: QuranSurahPlayButton.size)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A simple glass card with a title and a detail line, for the juz and bookmark lists.
private struct PlainListCard: View {
    let title: String
    let detail: String
    let symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(QuranPalette.gold)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(verbatim: detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
