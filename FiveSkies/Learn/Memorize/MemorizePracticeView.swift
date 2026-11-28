import SwiftUI

/// The three ways an ayah can be shown while practising.
enum MemorizeMode: String, CaseIterable, Identifiable {
    case read
    case hide
    case firstWords

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: return "Read"
        case .hide: return "Hide"
        case .firstWords: return "First words"
        }
    }
}

/// Practises one ayah at a time over a range, with the text exactly as stored.
struct MemorizePracticeView: View {
    let sura: Sura
    let range: ClosedRange<Int>
    @ObservedObject var progress: MemorizeProgressStore

    @EnvironmentObject private var quran: QuranStore
    @Environment(\.motionEnabled) private var motionEnabled

    @AppStorage(SurahReaderView.textSizeKey) private var textSize: Double = SurahReaderView.defaultTextSize

    @State private var position = 0
    @State private var mode: MemorizeMode = .read
    @State private var isRevealed = false
    @State private var isPeeking = false

    private var ayahs: [Ayah] {
        quran.ayahs(inSura: sura.number).filter { range.contains($0.number) }
    }

    private var refs: [AyahRef] {
        ayahs.map(\.ref)
    }

    private var size: CGFloat {
        CGFloat(min(max(textSize, SurahReaderView.textSizeRange.lowerBound), SurahReaderView.textSizeRange.upperBound))
    }

    var body: some View {
        let list = ayahs
        let index = min(max(position, 0), max(list.count - 1, 0))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(count: list.count, index: index)

                Picker("Mode", selection: $mode) {
                    ForEach(MemorizeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
                .accessibilityIdentifier("memorizeMode")

                if list.indices.contains(index) {
                    let ayah = list[index]
                    ayahCard(ayah)
                    controls(ayah: ayah, index: index, count: list.count)
                } else {
                    Text("These ayahs could not be found.")
                        .font(.headline)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .moreGlass(.dark, cornerRadius: 24)
                }

                summary
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: position) { _, _ in
            resetReveal()
        }
        .onChange(of: mode) { _, _ in
            resetReveal()
        }
    }

    private func resetReveal() {
        isRevealed = false
        isPeeking = false
    }

    // MARK: - Header

    private func header(count: Int, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MoreCaption(text: "Memorize")
            Text(verbatim: sura.transliteratedName)
                .font(.largeTitle.weight(.heavy))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("memorizePracticeTitle")
            if count > 0, ayahs.indices.contains(index) {
                Text(verbatim: "Ayah \(ayahs[index].number) · \(index + 1) of \(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityIdentifier("memorizePosition")
            }
        }
    }

    // MARK: - Ayah card

    private var isShowingText: Bool {
        mode == .read || isRevealed || isPeeking
    }

    private func arabic(_ text: String) -> some View {
        Text(verbatim: text)
            .font(QuranPalette.arabicFont(size: size))
            .lineSpacing(size * 0.6)
            .foregroundStyle(QuranPalette.arabicText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, size * 0.2)
            .quranSpeechLanguage("ar")
    }

    private func ayahCard(_ ayah: Ayah) -> some View {
        // Ayah 1 of most suras is practised without the basmala, as the reader shows it.
        let text = ayah.displayText
        let split = MemorizeText.firstWords(text, count: 2)
        let showing = isShowingText
        return VStack(alignment: .leading, spacing: 12) {
            arabic(text)
                .opacity(showing ? 1 : 0)
                .accessibilityHidden(!showing)
                .overlay(alignment: .topLeading) {
                    if !showing {
                        if mode == .firstWords {
                            firstWordsOverlay(split)
                        } else {
                            hiddenPanel
                        }
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
                .animation(motionEnabled ? .easeInOut(duration: 0.2) : nil, value: showing)

            HStack(spacing: 8) {
                if mode != .read {
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Label(isRevealed ? "Hide" : "Reveal", systemImage: isRevealed ? "eye.slash" : "eye")
                            .font(.subheadline.weight(.heavy))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityHint(Text("Shows or hides the ayah text"))
                    .accessibilityIdentifier("memorizeReveal")
                }
                statusChip(for: ayah.ref)
                Spacer(minLength: 4)
                AyahNumberMarker(number: ayah.number)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onLongPressGesture(minimumDuration: 60, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
            // Peeks while held; a very long minimum keeps it pressed until the finger lifts.
            guard mode != .read else { return }
            isPeeking = pressing
        })
        .accessibilityIdentifier("memorizeAyah")
    }

    private var hiddenPanel: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title3.weight(.semibold))
                    Text("Hold or tap Reveal to peek")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(8)
                .environment(\.layoutDirection, .leftToRight)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Ayah text hidden"))
            .accessibilityIdentifier("memorizeHidden")
    }

    private func firstWordsOverlay(_ split: MemorizeText.Split) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            arabic(split.prefix)
            if split.hasRemainder {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Rest of the ayah hidden"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("memorizeFirstWords")
    }

    @ViewBuilder
    private func statusChip(for ref: AyahRef) -> some View {
        switch progress.status(for: ref) {
        case .known:
            Text("Known")
                .font(.caption.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(MorePalette.mint))
        case .learning:
            Text("Learning")
                .font(.caption.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(MorePalette.goldLight))
        case .none:
            EmptyView()
        }
    }

    // MARK: - Controls

    private func controls(ayah: Ayah, index: Int, count: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                markButton(title: "Still learning", filled: false, identifier: "memorizeLearning") {
                    mark(ayah, as: .learning, index: index, count: count)
                }
                markButton(title: "I knew it", filled: true, identifier: "memorizeKnown") {
                    mark(ayah, as: .known, index: index, count: count)
                }
            }
            HStack(spacing: 10) {
                stepButton(title: "Previous", symbol: "chevron.left", identifier: "memorizePrevious", enabled: index > 0) {
                    position = index - 1
                }
                stepButton(title: "Next", symbol: "chevron.right", identifier: "memorizeNext", enabled: index < count - 1) {
                    position = index + 1
                }
            }
        }
    }

    private func mark(_ ayah: Ayah, as status: MemorizeStatus, index: Int, count: Int) {
        progress.mark(ayah.ref, as: status)
        if index < count - 1 {
            position = index + 1
        } else {
            resetReveal()
        }
    }

    private func markButton(title: String, filled: Bool, identifier: String, action: @escaping () -> Void) -> some View {
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

    private func stepButton(
        title: String,
        symbol: String,
        identifier: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .moreGlass(.light, cornerRadius: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Summary

    private var summary: some View {
        let total = refs.count
        let known = progress.knownCount(in: refs)
        return VStack(alignment: .leading, spacing: 8) {
            MoreCaption(text: "Progress")
            Text(verbatim: "\(known) of \(total) marked known")
                .font(.headline.weight(.heavy))
                .accessibilityIdentifier("memorizeSummary")
            ProgressView(value: Double(known), total: Double(max(total, 1)))
                .tint(MorePalette.mint)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }
}
