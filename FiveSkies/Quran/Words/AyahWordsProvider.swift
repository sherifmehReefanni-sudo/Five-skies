import Foundation

/// Where the Words sheet gets an ayah's words. Meanings load on demand and are never stored.
protocol AyahWordsProviding: Sendable {
    /// Quran Foundation's words for one ayah, in order, "end" markers removed. No Arabic.
    func words(sura: Int, ayah: Int) async throws -> [AyahWordEntry]
}

/// Failures the sheet shows as its error state.
enum AyahWordsError: Error, Equatable, Sendable {
    /// Not a real sura and ayah number.
    case invalidAyah
    /// The answer held no words.
    case empty
}

/// Words from the Quran Foundation Content API v4 through the Five Skies relay.
/// No cache: every call asks the relay, and the sheet keeps the answer in memory while it is open.
struct RelayAyahWordsProvider: AyahWordsProviding {
    static let chapterRange = 1...114

    /// `word_fields=location` keeps the word payload small; the Arabic fields that still arrive are not decoded.
    static func path(sura: Int, ayah: Int) -> String {
        "/api/v4/verses/by_key/\(sura):\(ayah)?words=true&language=en&word_fields=location"
    }

    private let client: any RelayFetching

    init(client: any RelayFetching) {
        self.client = client
    }

    func words(sura: Int, ayah: Int) async throws -> [AyahWordEntry] {
        guard Self.chapterRange.contains(sura), ayah >= 1, ayah <= 286 else {
            throw AyahWordsError.invalidAyah
        }
        let response = try await client.get(relativePath: Self.path(sura: sura, ayah: ayah), as: AyahWordsResponse.self)
        let entries = response.entries
        guard !entries.isEmpty else { throw AyahWordsError.empty }
        return entries
    }
}

/// Made-up words for UI tests and previews (`-FSFakeWords`). No relay calls and no Arabic: placeholder
/// English and Latin text only. Its audio links follow the real word file pattern, so a tapped play
/// button streams from the Quran Foundation audio host; the UI test never taps one.
/// Surah 1 gets as many words as our own split of the bundled text (so the screenshot shows aligned
/// rows) with transliteration and audio, like prelive; other surahs get three words with meanings only.
struct FakeAyahWordsProvider: AyahWordsProviding {
    /// Our word count for an ayah, or nil when unknown.
    let wordCount: @Sendable (Int, Int) async -> Int?

    init(wordCount: @escaping @Sendable (Int, Int) async -> Int? = FakeAyahWordsProvider.bundledWordCount) {
        self.wordCount = wordCount
    }

    func words(sura: Int, ayah: Int) async throws -> [AyahWordEntry] {
        let count: Int
        if sura == 1, let ours = await wordCount(sura, ayah), ours > 0 {
            count = ours
        } else {
            count = 3
        }
        return (1...count).map { position in
            let hasExtras = sura == 1
            return AyahWordEntry(
                position: position,
                meaning: "Sample meaning \(position)",
                transliteration: hasExtras ? "sample-\(position)" : nil,
                audioURL: hasExtras
                    ? AyahWordAudioURL.resolve("wbw/\(Self.pad(sura))_\(Self.pad(ayah))_\(Self.pad(position)).mp3")
                    : nil
            )
        }
    }

    /// Three digits, as in the word file names (`001`).
    static func pad(_ number: Int) -> String {
        let digits = String(number)
        return digits.count >= 3 ? digits : String(repeating: "0", count: 3 - digits.count) + digits
    }

    /// Loaded once, the first time the fake is asked, off the caller's thread.
    private static let bundledData: QuranData? = try? QuranBundle.load()

    /// Counts words in the string the reader draws (`Ayah.displayText`), by the W2 splitter.
    static let bundledWordCount: @Sendable (Int, Int) async -> Int? = { sura, ayah in
        await Task.detached(priority: .userInitiated) { () -> Int? in
            guard let match = FakeAyahWordsProvider.bundledData?.ayahs(inSura: sura).first(where: { $0.number == ayah }) else {
                return nil
            }
            return AyahWordSplitter.wordCount(in: match.displayText)
        }.value
    }
}

/// Picks the provider the app uses. Nil means no relay is configured: the sheet says it needs a
/// connection. Inside unit tests and `-FSFixedPhase` runs `RelayConfig.fromBundle()` gives nil, so no
/// network is ever used there; `-FSFakeWords` gives the fake, also under `-FSFixedPhase`.
enum AyahWordsProviderFactory {
    static let fakeArgument = "-FSFakeWords"

    static func live(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> (any AyahWordsProviding)? {
        if processInfo.arguments.contains(fakeArgument) {
            return FakeAyahWordsProvider()
        }
        guard let config = RelayConfig.fromBundle(bundle, processInfo: processInfo) else {
            return nil
        }
        return RelayAyahWordsProvider(client: RelayClient(config: config))
    }
}
