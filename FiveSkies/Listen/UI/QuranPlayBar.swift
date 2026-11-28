import SwiftUI

/// The bottom of the Quran tab and of the reader: a problem with a surah, the prayer pause,
/// the now playing bar, and in the reader "Play this surah" when nothing of it is playing.
/// The credit line is on every bar (D9).
struct QuranPlayBar: View {
    @EnvironmentObject private var player: ListenPlayer
    @EnvironmentObject private var navigator: QuranNavigator
    @ObservedObject var model: QuranListenModel

    /// The surah open in the reader, or nil on the surah list.
    let readerSura: Int?
    let readerSuraName: String?
    let onOpenPlayer: () -> Void

    @State private var taps = 0

    var body: some View {
        let offer = readerOffer
        if model.problem != nil || player.item != nil || offer != nil {
            VStack(spacing: 8) {
                if let problem = model.problem {
                    problemBanner(problem)
                }
                if let prayer = player.pausedForPrayer, player.item != nil {
                    ListenPrayerPauseBanner(prayer: prayer, identifier: "prayerPauseBanner")
                }
                if let offer {
                    playSurahCard(reciter: offer.reciter, chapter: offer.chapter, name: offer.name)
                }
                if let item = player.item {
                    // From anywhere else, the bar takes you to the playing ayah (U4);
                    // inside that surah's reader it opens the full player.
                    NowPlayingBar(item: item, onOpen: { openFromBar(item) })
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
        }
    }

    private func openFromBar(_ item: NowPlayingItem) {
        if readerSura == item.chapter {
            onOpenPlayer()
        } else {
            navigator.open(QuranReaderTarget(sura: item.chapter, aya: player.currentAyah))
        }
    }

    /// In the reader, when a reciter is chosen and this surah is not in the player.
    private var readerOffer: (reciter: Reciter, chapter: Int, name: String)? {
        guard let readerSura, let reciter = model.selectedReciter else { return nil }
        if player.item?.chapter == readerSura {
            return nil
        }
        return (reciter, readerSura, readerSuraName ?? "Surah \(readerSura)")
    }

    private func playSurahCard(reciter: Reciter, chapter: Int, name: String) -> some View {
        let isFetching = model.fetchingChapter == chapter
        let credit = ListenCreditLine.text(for: reciter)
        return Button {
            taps += 1
            model.play(chapter: chapter, name: name, on: player)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MorePalette.goldGradient)
                    if isFetching {
                        ProgressView()
                            .tint(MorePalette.ink)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(MorePalette.ink)
                            .offset(x: 1.5)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play this surah")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(verbatim: credit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .moreGlass(.dark, cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(isFetching)
        .accessibilityLabel(Text(verbatim: "Play this surah, \(name), \(credit)"))
        .accessibilityValue(Text(isFetching ? "Loading" : ""))
        .accessibilityIdentifier("readerPlaySurah")
    }

    private func problemBanner(_ problem: ListenPlayProblem) -> some View {
        HStack(spacing: 12) {
            Text(problem.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Retry") {
                taps += 1
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThickMaterial)
                .environment(\.colorScheme, .dark)
        )
        .moreGlass(.dark, cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("listenProblem")
    }
}

/// The compact reciter row at the top of the Quran tab: the chosen reciter and Change.
/// Names come from the API at run time and are shown exactly as given (D4).
struct QuranReciterRow: View {
    @ObservedObject var model: QuranListenModel
    let onChange: () -> Void

    var body: some View {
        switch model.recitersState {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Loading reciters")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .moreGlass(.dark, cornerRadius: 20)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("listenRecitersLoading")
        case .failed:
            retryRow(
                message: model.failureMessage ?? "Reciters could not load. Check your connection and try again.",
                identifier: "listenRecitersFailed"
            )
        case .loaded:
            if let reciter = model.selectedReciter {
                reciterButton(reciter)
            } else {
                retryRow(
                    message: "No reciters are available right now.",
                    identifier: "listenRecitersEmpty"
                )
            }
        }
    }

    private func reciterButton(_ reciter: Reciter) -> some View {
        Button(action: onChange) {
            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MorePalette.gold)
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    MoreCaption(text: "Reciter")
                    Text(verbatim: reciter.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Text("Change")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MorePalette.gold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .moreGlass(.dark, cornerRadius: 20)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(verbatim: "Reciter, \(ListenReciterPicker.accessibilityName(reciter))"))
        .accessibilityHint("Opens the list of reciters")
        .accessibilityIdentifier("listenReciterButton")
    }

    private func retryRow(message: String, identifier: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "headphones")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                model.reload()
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.gold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityHint("Loads the reciters again")
            .accessibilityIdentifier("\(identifier)Retry")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .moreGlass(.dark, cornerRadius: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The round play button on a surah row. Plays the surah with the chosen reciter, or
/// pauses and resumes it when it is the one in the player.
struct QuranSurahPlayButton: View {
    static let size: CGFloat = 38

    @EnvironmentObject private var player: ListenPlayer
    @ObservedObject var model: QuranListenModel
    let sura: Sura

    @State private var taps = 0

    var body: some View {
        let isCurrent = model.isCurrent(sura.number, in: player)
        let isPlaying = isCurrent && (player.state == .playing || player.state == .loading)
        let isFetching = model.fetchingChapter == sura.number
        Button {
            taps += 1
            model.playOrToggle(chapter: sura.number, name: sura.transliteratedName, on: player)
        } label: {
            ZStack {
                Circle()
                    .fill(isCurrent ? AnyShapeStyle(MorePalette.goldGradient) : AnyShapeStyle(Color.white.opacity(0.14)))
                if isFetching {
                    ProgressView()
                        .tint(isCurrent ? MorePalette.ink : .white)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(isCurrent ? MorePalette.ink : MorePalette.gold)
                        .offset(x: isPlaying ? 0 : 1)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityLabel(Text(verbatim: "\(isPlaying ? "Pause" : "Play") \(sura.transliteratedName)"))
        .accessibilityValue(Text(isFetching ? "Loading" : (isCurrent && player.state == .paused ? "Paused" : "")))
        .accessibilityIdentifier("quranPlay-\(sura.number)")
    }
}

/// Loads the reciters, hands the player its queue resolver once, and presents the
/// reciter list and the player sheet for the Quran tab.
struct QuranListenHost: ViewModifier {
    @EnvironmentObject private var player: ListenPlayer
    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var translations: TranslationStore
    @ObservedObject var model: QuranListenModel
    @Binding var showsReciters: Bool
    @Binding var showsPlayer: Bool

    @State private var sleepChoice = ListenSleepChoice()

    func body(content: Content) -> some View {
        content
            .onAppear {
                model.loadIfNeeded()
                model.connect(player, suras: quran.suras)
            }
            .onChange(of: quran.suras.count) { _, _ in
                model.connect(player, suras: quran.suras)
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
                ListenPlayerSheet(
                    sleepChoice: $sleepChoice,
                    hasTranslation: translations.selectedID != nil,
                    onReadingAids: {
                        UserDefaults.standard.set(true, forKey: ReadingPreferences.showsTranslationKey)
                        translations.showsTransliteration = true
                    }
                )
                    .environmentObject(player)
                    .environmentObject(quran)
            }
    }
}
