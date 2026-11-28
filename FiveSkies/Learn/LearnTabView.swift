import SwiftUI

/// The Learn tab (docs/LEARN_LISTEN_PLAN.md section 4, round E3): review, the Start here path,
/// Memorize, common words and the reading plan. Each card opens one screen; the Quran itself
/// opens in the Quran tab through `QuranNavigator`.
struct LearnTabView: View {
    enum Destination: Hashable {
        case review, path, memorize, words, plan
    }

    @EnvironmentObject private var quran: QuranStore
    @EnvironmentObject private var navigator: QuranNavigator
    @EnvironmentObject private var player: ListenPlayer
    @Environment(\.appClock) private var clock

    @State private var path: [Destination] = []
    @State private var wordsProvider: (any AyahWordsProviding)? = AyahWordsProviderFactory.live()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Small steps with the Quran, at your own pace.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .padding(.horizontal, 4)

                    card(
                        .review,
                        symbol: "arrow.triangle.2.circlepath",
                        title: "Review",
                        identifier: "learnOpenReview"
                    ) {
                        LearnReviewSummary(now: clock.now())
                    }
                    card(
                        .path,
                        symbol: "figure.walk",
                        title: "Start here",
                        identifier: "learnOpenPath"
                    ) {
                        LearnCardLine(text: "Short surahs in a gentle order")
                    }
                    card(
                        .memorize,
                        symbol: "brain.head.profile",
                        title: "Memorize",
                        identifier: "learnOpenMemorize"
                    ) {
                        LearnCardLine(text: "Practise any surah ayah by ayah")
                    }
                    card(
                        .words,
                        symbol: "textformat.abc",
                        title: "Common words",
                        identifier: "learnOpenWords"
                    ) {
                        LearnCardLine(text: "The words you will meet most often")
                    }
                    card(
                        .plan,
                        symbol: "calendar",
                        title: "Reading plan",
                        identifier: "learnOpenPlan"
                    ) {
                        ReadingPlanSummary()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .quranSkyBackground()
            .foregroundStyle(.white)
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Destination.self) { destination in
                screen(destination)
            }
        }
    }

    private func card<Detail: View>(
        _ destination: Destination,
        symbol: String,
        title: String,
        identifier: String,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        Button {
            path.append(destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(QuranPalette.gold)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                    detail()
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .moreGlass(.dark, cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func screen(_ destination: Destination) -> some View {
        if let data = quran.data {
            switch destination {
            case .review:
                LearnReviewView()
            case .path:
                StartHereView(data: data, onLearn: learn, onOpen: open)
            case .memorize:
                MemorizeView()
            case .words:
                CommonWordsView(data: data, provider: wordsProvider, onOpen: open)
            case .plan:
                ReadingPlanView(data: data, onOpen: open)
            }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .quranSkyBackground()
        }
    }

    private func open(_ target: QuranReaderTarget) {
        navigator.open(target)
    }

    /// The guided lesson is the reader in the Memorize preset (docs/READER_EASE_PLAN.md E2.1):
    /// each ayah three times, then your turn with the text hidden.
    private func learn(_ sura: Int) {
        player.modes = ListenPreset.memorize.applied(to: player.modes)
        navigator.open(QuranReaderTarget(sura: sura, aya: nil))
    }
}

/// One quiet line under a Learn card title.
struct LearnCardLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MorePalette.secondaryText)
    }
}
