import SwiftUI

/// One common word: its stored form, how often it appears, where it first appears, and its meaning
/// and transliteration from Quran Foundation's word list for that ayah, loaded when the sheet opens.
/// Nothing is stored. Suggested detents: `[.medium, .large]`.
struct CommonWordDetailSheet: View {
    let entry: CommonWordEntry
    let data: QuranData
    /// For "Rank 1 of 20,718". Nil hides the "of" part.
    let distinctFormCount: Int?
    let provider: (any AyahWordsProviding)?
    let onOpen: (QuranReaderTarget) -> Void

    private enum MeaningState {
        case loading
        case found(meaning: String?, transliteration: String?)
        case notAligned
        case failed(String)
    }

    @State private var state: MeaningState = .loading
    @State private var attempt = 0

    @ScaledMetric(relativeTo: .largeTitle) private var arabicSize: CGFloat = 52

    init(
        entry: CommonWordEntry,
        data: QuranData,
        distinctFormCount: Int?,
        provider: (any AyahWordsProviding)?,
        onOpen: @escaping (QuranReaderTarget) -> Void
    ) {
        self.entry = entry
        self.data = data
        self.distinctFormCount = distinctFormCount
        self.provider = provider
        self.onOpen = onOpen
    }

    private var occurrence: CommonWordOccurrence { entry.firstOccurrence }

    private var suraName: String {
        data.sura(occurrence.sura)?.transliteratedName ?? "Surah \(occurrence.sura)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                meaningCard
                exampleCard
                if provider != nil {
                    Text(CommonWordsText.creditLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("commonWordCredit")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .quranSkyBackground()
        .accessibilityIdentifier("commonWordDetail")
        .task(id: attempt) {
            await loadMeaning()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreCaption(text: "Common word")
            Text(verbatim: entry.form)
                .font(QuranPalette.arabicFont(size: arabicSize))
                .foregroundStyle(QuranPalette.arabicText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .environment(\.layoutDirection, .rightToLeft)
                .quranSpeechLanguage("ar")
                .accessibilityIdentifier("commonWordForm")
            Text(verbatim: countLine)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .accessibilityIdentifier("commonWordCount")
            Text(verbatim: rankLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
        }
    }

    private var countLine: String {
        let appears = CommonWordsText.appears(entry.count)
        return "This word " + appears + " in the Quran"
    }

    private var rankLine: String {
        if let distinctFormCount {
            return "Number \(entry.rank) of \(CommonWordsText.number(distinctFormCount)) written forms"
        }
        return "Number \(entry.rank)"
    }

    // MARK: - Meaning

    @ViewBuilder
    private var meaningCard: some View {
        if provider == nil {
            messageCard(CommonWordsText.needsConnectionLine, symbol: "wifi", identifier: "commonWordUnavailable")
        } else {
            switch state {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading the meaning")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 20)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("commonWordLoading")
            case .found(meaning: let meaning, transliteration: let transliteration):
                if meaning == nil, transliteration == nil {
                    messageCard(CommonWordsText.notAlignedLine, symbol: "info.circle", identifier: "commonWordNotAligned")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        MoreCaption(text: "Meaning")
                        if let transliteration {
                            Text(verbatim: transliteration)
                                .font(.body.italic())
                                .foregroundStyle(QuranPalette.gold)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("commonWordTransliteration")
                        }
                        if let meaning {
                            Text(verbatim: meaning)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("commonWordMeaning")
                        }
                        Text("Meaning of the word in this ayah")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MorePalette.secondaryText)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .moreGlass(.dark, cornerRadius: 20)
                }
            case .notAligned:
                messageCard(CommonWordsText.notAlignedLine, symbol: "info.circle", identifier: "commonWordNotAligned")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 14) {
                    Text(message)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        attempt += 1
                    } label: {
                        Text("Try again")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(MorePalette.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(MorePalette.goldGradient))
                    }
                    .buttonStyle(PressScaleButtonStyle(pressedScale: 0.95))
                    .accessibilityIdentifier("commonWordRetry")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 20)
                .accessibilityIdentifier("commonWordError")
            }
        }
    }

    // MARK: - Example

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            MoreCaption(text: "First appears in")
            Text(verbatim: CommonWordsText.example(suraName: suraName, occurrence: occurrence))
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .accessibilityIdentifier("commonWordExample")
            Button {
                onOpen(QuranReaderTarget(sura: occurrence.sura, aya: occurrence.aya))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .accessibilityHidden(true)
                    Text("Open in the Quran")
                }
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(MorePalette.goldGradient))
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.95))
            .accessibilityIdentifier("commonWordOpen")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 20)
    }

    private func messageCard(_ text: String, symbol: String, identifier: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(QuranPalette.gold)
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Loading

    @MainActor
    private func loadMeaning() async {
        guard let provider else { return }
        guard let ayah = data.ayah(occurrence.ref) else {
            state = .notAligned
            return
        }
        state = .loading
        let storedText = ayah.displayText
        do {
            let entries = try await provider.words(sura: occurrence.sura, ayah: occurrence.aya)
            guard !Task.isCancelled else { return }
            let lookup = CommonWordMeaning.lookup(
                storedText: storedText,
                entries: entries,
                wordPosition: occurrence.wordPosition,
                form: entry.form
            )
            if let row = lookup {
                state = .found(meaning: row.meaning, transliteration: row.transliteration)
            } else {
                state = .notAligned
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(AyahWordsSheet.message(for: error))
        }
    }
}

/// Picks the word's row from Quran Foundation's list for its ayah. Pure.
enum CommonWordMeaning {
    /// The row at `wordPosition`, only when the ayah lines up (rule W3) and that row's slice is
    /// exactly `form`. Otherwise nil, and the sheet says the meaning is not available yet.
    static func lookup(storedText: String, entries: [AyahWordEntry], wordPosition: Int, form: String) -> AyahWordRow? {
        let built = AyahWordsBuilder.rows(storedText: storedText, entries: entries)
        guard built.aligned,
              let row = built.rows.first(where: { $0.position == wordPosition }),
              let arabic = row.arabic,
              CommonWordsIndex.formKey(arabic) == form
        else {
            return nil
        }
        return row
    }
}
