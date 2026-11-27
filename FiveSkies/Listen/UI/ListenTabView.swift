import SwiftUI

/// The Listen tab: choose a reciter, tap a surah, and it streams from Quran Foundation.
/// Reciter names come from the API at run time and are shown exactly as given (D4).
/// Every player shows the credit line (D9). Surah names come from the bundled metadata,
/// in English letters only.
struct ListenTabView: View {
    @EnvironmentObject private var player: ListenPlayer
    @EnvironmentObject private var quran: QuranStore
    @StateObject private var model: ListenTabModel

    @State private var revealed = false
    @State private var showsReciters = false
    @State private var showsPlayer = false
    @State private var sleepChoice = ListenSleepChoice()
    @State private var rowTaps = 0

    init() {
        _model = StateObject(wrappedValue: ListenTabModel(catalog: ListenCatalogFactory.live()))
    }

    init(catalog: any ListenCatalog, defaults: UserDefaults = .standard) {
        _model = StateObject(wrappedValue: ListenTabModel(catalog: catalog, defaults: defaults))
    }

    var body: some View {
        ZStack {
            Color.clear.moreSkyBackground(.tasbih)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Listen")
                        .font(.largeTitle.weight(.heavy))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("listenTitle")
                        .riseIn(revealed: revealed, delay: 0)

                    reciterSection
                        .riseIn(revealed: revealed, delay: 0.08)

                    surahSection
                        .riseIn(revealed: revealed, delay: 0.16)

                    Text("Recitations stream from Quran Foundation, so you need a connection.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInset
            }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .light), trigger: rowTaps)
        .onAppear {
            revealed = true
            model.loadIfNeeded()
        }
        .onChange(of: player.item == nil) { _, isEmpty in
            if isEmpty {
                showsPlayer = false
            }
        }
        .sheet(isPresented: $showsReciters) {
            ListenReciterPicker(model: model)
        }
        .sheet(isPresented: $showsPlayer) {
            ListenPlayerSheet(sleepChoice: $sleepChoice)
                .environmentObject(player)
        }
    }

    // MARK: - Reciter

    @ViewBuilder
    private var reciterSection: some View {
        switch model.recitersState {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading reciters")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(18)
            .moreGlass(.dark, cornerRadius: 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("listenRecitersLoading")
        case .failed:
            ListenProblemCard(
                message: "Reciters could not load. Check your connection and try again.",
                identifier: "listenRecitersFailed"
            ) {
                model.reload()
            }
        case .loaded:
            if let reciter = model.selectedReciter {
                reciterButton(reciter)
            } else {
                ListenProblemCard(
                    message: "No reciters are available right now. Try again in a little while.",
                    identifier: "listenRecitersEmpty"
                ) {
                    model.reload()
                }
            }
        }
    }

    private func reciterButton(_ reciter: Reciter) -> some View {
        Button {
            showsReciters = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MorePalette.gold)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    MoreCaption(text: "Reciter")
                    Text(verbatim: reciter.name)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let style = reciter.style, !style.isEmpty {
                        Text(verbatim: style)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Text("Change")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .moreGlass(.light, cornerRadius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(verbatim: "Reciter, \(ListenReciterPicker.accessibilityName(reciter))"))
        .accessibilityHint("Opens the list of reciters")
        .accessibilityIdentifier("listenReciterButton")
    }

    // MARK: - Surahs

    private var surahSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MoreCaption(text: "Surahs")
                .padding(.horizontal, 4)
            switch quran.state {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading surahs")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 24)
                .accessibilityElement(children: .combine)
            case .failed:
                Text("The surah list could not be opened.")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .moreGlass(.dark, cornerRadius: 24)
            case .loaded(let data):
                LazyVStack(spacing: 8) {
                    ForEach(data.suras) { sura in
                        surahRow(sura)
                    }
                }
            }
        }
    }

    private func surahRow(_ sura: Sura) -> some View {
        let isCurrent = player.item?.chapter == sura.number
        let isFetching = model.fetchingChapter == sura.number
        return Button {
            rowTaps += 1
            tap(sura, isCurrent: isCurrent)
        } label: {
            ListenSurahRowLabel(
                sura: sura,
                isCurrent: isCurrent,
                isPlaying: isCurrent && player.state == .playing,
                isFetching: isFetching
            )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(verbatim: "\(sura.number), \(sura.transliteratedName), \(sura.englishName)"))
        .accessibilityValue(Text(status(isCurrent: isCurrent, isFetching: isFetching)))
        .accessibilityHint(Text(isCurrent ? "Plays or pauses this surah" : "Plays this surah"))
        .accessibilityIdentifier("listenSurah-\(sura.number)")
    }

    /// The current surah with the same reciter toggles play and pause; anything else starts fresh.
    private func tap(_ sura: Sura, isCurrent: Bool) {
        let sameReciter = player.item?.reciter.id == model.selectedReciter?.id
        if isCurrent, sameReciter, player.state == .playing || player.state == .paused {
            player.togglePlayPause()
        } else {
            model.play(chapter: sura.number, name: sura.transliteratedName, on: player)
        }
    }

    private func status(isCurrent: Bool, isFetching: Bool) -> String {
        if isFetching {
            return "Loading"
        }
        guard isCurrent else { return "" }
        switch player.state {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .loading: return "Loading"
        case .failed: return "Could not play"
        case .idle: return ""
        }
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottomInset: some View {
        if model.problem != nil || player.item != nil {
            VStack(spacing: 8) {
                if let problem = model.problem {
                    problemBanner(problem)
                }
                if let item = player.item {
                    NowPlayingBar(item: item) {
                        showsPlayer = true
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func problemBanner(_ problem: ListenPlayProblem) -> some View {
        HStack(spacing: 12) {
            Text(problem.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Retry") {
                model.retry(on: player)
            }
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(MorePalette.gold)
            .accessibilityHint("Tries this surah again")
            .accessibilityIdentifier("listenProblemRetry")
            Button {
                model.dismissProblem()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("listenProblemDismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .moreGlass(.dark, cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listenProblem")
    }
}

/// One surah in the Listen list: number, English letters name, English meaning,
/// and the playing bars on the current one.
private struct ListenSurahRowLabel: View {
    let sura: Sura
    let isCurrent: Bool
    let isPlaying: Bool
    let isFetching: Bool

    var body: some View {
        HStack(spacing: 12) {
            SuraNumberBadge(number: sura.number)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sura.transliteratedName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isCurrent ? MorePalette.goldLight : .white)
                Text(verbatim: sura.englishName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            Spacer(minLength: 8)
            if isFetching {
                ProgressView()
                    .tint(.white)
            } else if isCurrent {
                ListenPlayingIndicator(isPlaying: isPlaying)
            } else {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(isCurrent ? .light : .dark, cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A friendly message with a Retry button.
private struct ListenProblemCard: View {
    let message: String
    let identifier: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Text("Retry")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(MorePalette.goldGradient))
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityHint("Loads the reciters again")
            .accessibilityIdentifier("\(identifier)Retry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
