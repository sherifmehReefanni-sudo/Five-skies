import SwiftUI

/// The words of the Review screens, kept apart so tests can check them.
enum LearnReviewText {
    static let title = "Review"
    static let empty = "Nothing to review today. Ayahs you mark known come back here after 1, 3, 7, 14 and 30 days."

    /// "Al-Baqara 2:255", or "Surah 2:255" while the Quran is still loading.
    static func reference(_ ref: AyahRef, suraName: String?) -> String {
        let name = suraName ?? "Surah"
        return "\(name) \(ref.sura):\(ref.aya)"
    }

    /// "3 ayahs to review today", "1 ayah to review today" or "Nothing to review today".
    static func summary(count: Int) -> String {
        if count <= 0 {
            return "Nothing to review today"
        }
        return count == 1 ? "1 ayah to review today" : "\(count) ayahs to review today"
    }
}

/// Review (docs/LEARN_LISTEN_PLAN.md L3): the known ayahs that are due today, in Quran order.
/// A row opens the review card. Pushed inside the Learn tab's NavigationStack.
struct LearnReviewView: View {
    @EnvironmentObject private var quran: QuranStore
    @Environment(\.appClock) private var clock
    @ObservedObject private var progress = MemorizeProgressStore.shared

    @State private var selected: AyahRef?

    init() {}

    var body: some View {
        let due = progress.dueForReview(now: clock.now())
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    MoreScreenTitle(text: LearnReviewText.title, identifier: "learnReview")
                    if !due.isEmpty {
                        Text("Recite each ayah from memory, then peek to check.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 4)

                if due.isEmpty {
                    Text(LearnReviewText.empty)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .moreGlass(.dark, cornerRadius: 24)
                        .accessibilityIdentifier("learnReviewEmpty")
                } else {
                    ForEach(due, id: \.self) { ref in
                        row(ref)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationTitle(LearnReviewText.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selected) { ref in
            LearnReviewCard(start: ref)
        }
    }

    private func row(_ ref: AyahRef) -> some View {
        let reference = LearnReviewText.reference(ref, suraName: quran.sura(ref.sura)?.transliteratedName)
        return Button {
            selected = ref
        } label: {
            HStack(spacing: 12) {
                SuraNumberBadge(number: ref.sura)
                Text(verbatim: reference)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .moreGlass(.light, cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text(verbatim: reference))
        .accessibilityHint(Text("Opens the review card"))
        .accessibilityIdentifier("reviewRow-\(ref.sura)-\(ref.aya)")
    }
}

/// One line for the Review card on the Learn tab. Follows `now`; no timer of its own.
struct LearnReviewSummary: View {
    let now: Date

    @ObservedObject private var progress = MemorizeProgressStore.shared

    init(now: Date) {
        self.now = now
    }

    var body: some View {
        Text(LearnReviewText.summary(count: progress.dueForReview(now: now).count))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MorePalette.secondaryText)
            .accessibilityIdentifier("learnReviewSummary")
    }
}
