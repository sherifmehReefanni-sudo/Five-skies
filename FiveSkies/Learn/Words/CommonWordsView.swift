import SwiftUI

/// Common words (plan L4): the most frequent written word forms, counted on the device from the
/// bundled text. Pushed inside the Learn tab's NavigationStack, so it has no stack of its own.
struct CommonWordsView: View {
    let data: QuranData
    let provider: (any AyahWordsProviding)?
    let onOpen: (QuranReaderTarget) -> Void

    @State private var index: CommonWordsIndex?
    @State private var topCount = CommonWordsText.defaultChoice
    @State private var selected: CommonWordEntry?

    init(data: QuranData, provider: (any AyahWordsProviding)?, onOpen: @escaping (QuranReaderTarget) -> Void) {
        self.data = data
        self.provider = provider
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    MoreCaption(text: "Learn")
                    MoreScreenTitle(text: "Common words", identifier: "commonWordsTitle")
                }

                if let index {
                    loaded(index)
                } else {
                    loading
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("commonWords")
        .task {
            await loadIndex()
        }
        .sheet(item: $selected) { entry in
            CommonWordDetailSheet(
                entry: entry,
                data: data,
                distinctFormCount: index?.distinctFormCount,
                provider: provider,
                onOpen: { target in
                    selected = nil
                    onOpen(target)
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.selection, trigger: topCount)
    }

    @MainActor
    private func loadIndex() async {
        guard index == nil else { return }
        let built = await CommonWordsIndexLoader.shared.index(for: data)
        index = built
    }

    // MARK: - States

    private var loading: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Counting the words")
                .font(.body.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commonWordsLoading")
    }

    @ViewBuilder
    private func loaded(_ index: CommonWordsIndex) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CommonWordsText.headline(index: index, top: topCount))
                .font(.title3.weight(.heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("commonWordsHeadline")
            Text(CommonWordsText.totals(index: index))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("commonWordsTotals")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)

        Picker("Show", selection: $topCount) {
            ForEach(CommonWordsText.choices, id: \.self) { choice in
                Text(verbatim: "\(choice)").tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
        .accessibilityIdentifier("commonWordsTop")

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(QuranPalette.gold)
                .accessibilityHidden(true)
            Text(CommonWordsText.note)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("commonWordsNote")

        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(index.top(topCount)) { entry in
                Button {
                    selected = entry
                } label: {
                    CommonWordRowView(entry: entry)
                }
                .buttonStyle(PressScaleButtonStyle(pressedScale: 0.97))
                .accessibilityIdentifier("commonWord-\(entry.rank)")
                .accessibilityHint("Shows the meaning and the first place it appears")
            }
        }
    }
}

/// One row: rank, the stored Arabic form, and how often it appears.
private struct CommonWordRowView: View {
    let entry: CommonWordEntry

    @ScaledMetric(relativeTo: .title) private var arabicSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: "\(entry.rank)")
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(QuranPalette.gold)
                .frame(minWidth: 36, alignment: .leading)
            Text(CommonWordsText.appears(entry.count))
                .font(.body.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: entry.form)
                .font(QuranPalette.arabicFont(size: arabicSize))
                .foregroundStyle(QuranPalette.arabicText)
                .lineLimit(1)
                .fixedSize()
                .environment(\.layoutDirection, .rightToLeft)
                .quranSpeechLanguage("ar")
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .moreGlass(.dark, cornerRadius: 20)
    }
}
