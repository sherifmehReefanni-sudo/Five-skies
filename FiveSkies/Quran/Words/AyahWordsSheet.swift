import SwiftUI

/// The Words sheet behind the ayah toolbar's Words button (round E2.2): the ayah's words in order,
/// each with its slice of the stored Arabic (only when the ayah lines up, rule W3), transliteration,
/// meaning and a play button when a recording exists.
///
/// Meanings load when the sheet opens and live only as long as it does. Word audio streams and
/// stops when the sheet closes. Suggested detents: `[.medium, .large]`.
struct AyahWordsSheet: View {
    let ayah: Ayah
    /// Exactly the string the reader draws for this ayah (`ayah.displayText`).
    let storedText: String
    /// "Surah name · Ayah n", from the lead (`AyahToolbarText.title`).
    let title: String
    let provider: (any AyahWordsProviding)?

    private enum LoadState {
        case loading
        case loaded(rows: [AyahWordRow], aligned: Bool)
        case failed(String)
    }

    @StateObject private var audio: AyahWordAudio
    @State private var state: LoadState = .loading
    @State private var attempt = 0

    static let creditLine = "Word meanings and audio: Quran Foundation"
    static let notAlignedLine = "Word view is not available for this ayah"
    static let needsConnectionLine = "Word by word needs a connection"

    init(
        ayah: Ayah,
        storedText: String,
        title: String,
        provider: (any AyahWordsProviding)?,
        pauseRecitation: (() -> Void)? = nil
    ) {
        self.ayah = ayah
        self.storedText = storedText
        self.title = title
        self.provider = provider
        _audio = StateObject(wrappedValue: AyahWordAudio(pauseRecitation: pauseRecitation))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
                if provider != nil {
                    Text(Self.creditLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .accessibilityIdentifier("wordsCredit")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
        .quranSkyBackground()
        .accessibilityIdentifier("wordsSheet")
        .task(id: attempt) {
            await load()
        }
        .onDisappear {
            audio.stop()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Word by word")
                .font(.title2.weight(.heavy))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("wordsTitle")
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityIdentifier("wordsSubtitle")
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if provider == nil {
            messageCard(Self.needsConnectionLine, symbol: "wifi", identifier: "wordsUnavailable")
        } else {
            switch state {
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading words")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 20)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wordsLoading")
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
                    .accessibilityIdentifier("wordsRetry")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .moreGlass(.dark, cornerRadius: 20)
                .accessibilityIdentifier("wordsError")
            case .loaded(rows: let rows, aligned: let aligned):
                VStack(alignment: .leading, spacing: 12) {
                    if !aligned {
                        messageCard(Self.notAlignedLine, symbol: "info.circle", identifier: "wordsNotAligned")
                    }
                    // By offset: when the ayah does not line up, the API's numbers are not trusted to be unique.
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        AyahWordRowView(
                            row: row,
                            isPlaying: audio.playingPosition == row.position,
                            onPlay: { url in
                                audio.toggle(position: row.position, url: url)
                            }
                        )
                    }
                }
            }
        }
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
    private func load() async {
        guard let provider else { return }
        state = .loading
        let sura = ayah.sura
        let number = ayah.number
        do {
            let entries = try await provider.words(sura: sura, ayah: number)
            guard !Task.isCancelled else { return }
            let built = AyahWordsBuilder.rows(storedText: storedText, entries: entries)
            state = .loaded(rows: built.rows, aligned: built.aligned)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            state = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        if let relay = error as? RelayError {
            switch relay {
            case .transport:
                return "No connection. Try again when you are online."
            case .rateLimited:
                return "Too many requests. Try again in a minute."
            case .notConfigured:
                return needsConnectionLine
            default:
                break
            }
        }
        return "The words could not be loaded. Try again."
    }
}

/// One word: its Arabic slice on the right (when aligned), then transliteration, meaning and play.
private struct AyahWordRowView: View {
    let row: AyahWordRow
    let isPlaying: Bool
    let onPlay: (URL) -> Void

    @ScaledMetric(relativeTo: .title) private var arabicSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let arabic = row.arabic {
                Text(verbatim: arabic)
                    .font(QuranPalette.arabicFont(size: arabicSize))
                    .foregroundStyle(QuranPalette.arabicText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, arabicSize * 0.15)
                    .environment(\.layoutDirection, .rightToLeft)
                    .quranSpeechLanguage("ar")
                    .accessibilityIdentifier("wordArabic-\(row.position)")
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Word \(row.position)")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(QuranPalette.gold.opacity(0.8))
                    if let transliteration = row.transliteration {
                        Text(verbatim: transliteration)
                            .font(.body.italic())
                            .foregroundStyle(QuranPalette.gold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let meaning = row.meaning {
                        Text(verbatim: meaning)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let url = row.audioURL {
                    Button {
                        onPlay(url)
                    } label: {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.body.weight(.heavy))
                            .foregroundStyle(MorePalette.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(MorePalette.goldGradient))
                    }
                    .buttonStyle(PressScaleButtonStyle(pressedScale: 0.92))
                    .accessibilityLabel(isPlaying ? "Stop word \(row.position)" : "Play word \(row.position)")
                    .accessibilityIdentifier("wordPlay-\(row.position)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 20)
    }
}
