import SwiftUI

/// One review: recite the ayah from memory, peek at the stored text if needed, then answer.
/// After an answer it moves to the next ayah due today, or back to the list when none is left.
/// The Arabic is only ever the stored `ayah.displayText`, drawn as the reader draws it.
struct LearnReviewCard: View {
    @EnvironmentObject private var quran: QuranStore
    @Environment(\.appClock) private var clock
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progress = MemorizeProgressStore.shared

    @AppStorage(SurahReaderView.textSizeKey) private var textSize: Double = SurahReaderView.defaultTextSize

    @State private var current: AyahRef
    @State private var isPeeking = false
    @State private var answers = 0

    init(start: AyahRef) {
        _current = State(initialValue: start)
    }

    private var size: CGFloat {
        CGFloat(min(max(textSize, SurahReaderView.textSizeRange.lowerBound), SurahReaderView.textSizeRange.upperBound))
    }

    private var ayah: Ayah? {
        quran.ayahs(inSura: current.sura).first { $0.number == current.aya }
    }

    var body: some View {
        let reference = LearnReviewText.reference(current, suraName: quran.sura(current.sura)?.transliteratedName)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    MoreCaption(text: LearnReviewText.title)
                    Text(verbatim: reference)
                        .font(.largeTitle.weight(.heavy))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("reviewCardTitle")
                    Text("Recite it from memory")
                        .font(.headline)
                        .foregroundStyle(MorePalette.secondaryText)
                }

                ayahPanel

                answerButtons
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: answers)
        .onChange(of: current) { _, _ in
            isPeeking = false
        }
    }

    // MARK: - Ayah

    private var ayahPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPeeking, let ayah {
                Text(verbatim: ayah.displayText)
                    .font(QuranPalette.arabicFont(size: size))
                    .lineSpacing(size * 0.6)
                    .foregroundStyle(QuranPalette.arabicText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, size * 0.2)
                    .environment(\.layoutDirection, .rightToLeft)
                    .quranSpeechLanguage("ar")
                    .accessibilityIdentifier("reviewAyahText")
                    .transition(.opacity)
            } else if isPeeking {
                Text("This ayah could not be found.")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title3.weight(.semibold))
                    Text("Ayah text hidden")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Ayah text hidden"))
                .accessibilityIdentifier("reviewHidden")
            }

            HStack {
                Button {
                    isPeeking.toggle()
                } label: {
                    Label(isPeeking ? "Hide" : "Peek", systemImage: isPeeking ? "eye.slash" : "eye")
                        .font(.subheadline.weight(.heavy))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityHint(Text("Shows or hides the ayah text"))
                .accessibilityIdentifier("reviewPeek")
                Spacer(minLength: 4)
                AyahNumberMarker(number: current.aya)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .animation(motionEnabled ? .easeInOut(duration: 0.2) : nil, value: isPeeking)
    }

    // MARK: - Answers

    private var answerButtons: some View {
        VStack(spacing: 10) {
            answerButton(title: "I remembered it", filled: true, identifier: "reviewRemembered") {
                answer(remembered: true)
            }
            answerButton(title: "Needs practice", filled: false, identifier: "reviewPractice") {
                answer(remembered: false)
            }
        }
    }

    private func answer(remembered: Bool) {
        let now = clock.now()
        let answered = current
        progress.recordReview(answered, remembered: remembered, at: now)
        answers += 1
        if let next = progress.dueForReview(now: now).first(where: { $0 != answered }) {
            current = next
        } else {
            dismiss()
        }
    }

    private func answerButton(title: String, filled: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(filled ? MorePalette.ink : .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Capsule().fill(filled ? AnyShapeStyle(MorePalette.goldGradient) : AnyShapeStyle(Color.white.opacity(0.14)))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0.8 : 0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}
