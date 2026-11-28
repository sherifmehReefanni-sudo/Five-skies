import XCTest
@testable import FiveSkies

/// A relay that answers from canned JSON by exact relative path. Unknown paths act as offline.
final class WordsFakeRelay: RelayFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Data] = [:]
    private var log: [String] = []

    func serve(_ path: String, json: String) {
        lock.withLock { answers[path] = Data(json.utf8) }
    }

    var requested: [String] {
        lock.withLock { log }
    }

    func data(relativePath: String) async throws -> Data {
        let answer: Data? = lock.withLock {
            log.append(relativePath)
            return answers[relativePath]
        }
        guard let answer else { throw RelayError.transport }
        return answer
    }
}

/// Round E2.2: the Words sheet's pure logic. Test strings are built from code points; no Arabic in source.
final class AyahWordsTests: XCTestCase {
    // MARK: - Synthetic stored text

    private static func scalar(_ value: UInt32) -> String {
        String(UnicodeScalar(value)!)
    }

    /// Letter, mark, letter: a three scalar word made of Arabic letters and a fatha.
    private static func word(_ first: UInt32, _ second: UInt32) -> String {
        scalar(first) + scalar(0x064E) + scalar(second)
    }

    private static let wordOne = word(0x0628, 0x0627)
    private static let wordTwo = word(0x0645, 0x0646)
    private static let wordThree = word(0x0644, 0x0647)
    /// A small high pause mark (a non-spacing mark), a sign-only token.
    private static let pauseSign = scalar(0x06D6)

    /// Three words with a pause sign token after word two: "w1 w2 sign w3".
    private static let storedText = wordOne + " " + wordTwo + " " + pauseSign + " " + wordThree

    private func entries(_ positions: [Int]) -> [AyahWordEntry] {
        positions.map {
            AyahWordEntry(position: $0, meaning: "Meaning \($0)", transliteration: "word-\($0)", audioURL: nil)
        }
    }

    private static func containsArabicScalar(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) || (0xFB50...0xFEFF).contains($0.value) }
    }

    // MARK: - Builder

    func testSyntheticTextHasThreeWords() {
        XCTAssertEqual(AyahWordSplitter.wordCount(in: Self.storedText), 3)
    }

    func testAlignedRowsAreExactSlicesOfTheStoredString() {
        let result = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([1, 2, 3]))
        XCTAssertTrue(result.aligned)
        XCTAssertEqual(result.rows.map(\.position), [1, 2, 3])
        XCTAssertEqual(result.rows[0].arabic, Self.wordOne)
        // The sign token belongs to word two, with the space between them, nothing trimmed or added.
        XCTAssertEqual(result.rows[1].arabic, Self.wordTwo + " " + Self.pauseSign)
        XCTAssertEqual(result.rows[2].arabic, Self.wordThree)

        let ranges = AyahWordSplitter.wordRanges(in: Self.storedText)
        for (row, range) in zip(result.rows, ranges) {
            let expected = Array(Self.storedText.unicodeScalars[range])
            XCTAssertEqual(row.arabic.map { Array($0.unicodeScalars) }, expected)
        }
        XCTAssertEqual(result.rows[1].meaning, "Meaning 2")
        XCTAssertEqual(result.rows[1].transliteration, "word-2")
    }

    func testAlignedRowsFollowWordNumbersNotApiOrder() {
        let result = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([2, 1, 3]))
        XCTAssertTrue(result.aligned)
        XCTAssertEqual(result.rows.map(\.position), [1, 2, 3])
        XCTAssertEqual(result.rows[0].arabic, Self.wordOne)
        XCTAssertEqual(result.rows[0].meaning, "Meaning 1")
    }

    func testCountMismatchShowsMeaningsWithoutArabic() {
        let result = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([1, 2]))
        XCTAssertFalse(result.aligned)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows.allSatisfy { $0.arabic == nil })
        XCTAssertEqual(result.rows.map(\.meaning), ["Meaning 1", "Meaning 2"])
        XCTAssertEqual(result.rows.map(\.transliteration), ["word-1", "word-2"])

        let more = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([1, 2, 3, 4]))
        XCTAssertFalse(more.aligned)
        XCTAssertTrue(more.rows.allSatisfy { $0.arabic == nil })
    }

    func testPositionGapOrDuplicateIsNotAligned() {
        let gap = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([1, 2, 4]))
        XCTAssertFalse(gap.aligned)
        XCTAssertTrue(gap.rows.allSatisfy { $0.arabic == nil })

        let duplicate = AyahWordsBuilder.rows(storedText: Self.storedText, entries: entries([1, 2, 2]))
        XCTAssertFalse(duplicate.aligned)
        XCTAssertTrue(duplicate.rows.allSatisfy { $0.arabic == nil })
    }

    func testEmptyEntriesOrTextIsNotAligned() {
        XCTAssertFalse(AyahWordsBuilder.rows(storedText: Self.storedText, entries: []).aligned)
        let latinOnly = AyahWordsBuilder.rows(storedText: "abc def", entries: entries([1, 2]))
        XCTAssertFalse(latinOnly.aligned)
        XCTAssertTrue(latinOnly.rows.allSatisfy { $0.arabic == nil })
    }

    // MARK: - Audio URLs

    func testAudioURLResolution() {
        XCTAssertEqual(
            AyahWordAudioURL.resolve("wbw/001_001_001.mp3")?.absoluteString,
            "https://audio.qurancdn.com/wbw/001_001_001.mp3"
        )
        XCTAssertNil(AyahWordAudioURL.resolve("//wbw/001_001_002.mp3"))
        XCTAssertEqual(
            AyahWordAudioURL.resolve("/wbw/001_001_002.mp3")?.absoluteString,
            "https://audio.qurancdn.com/wbw/001_001_002.mp3"
        )
        XCTAssertEqual(
            AyahWordAudioURL.resolve("  wbw/001_001_003.mp3 ")?.absoluteString,
            "https://audio.qurancdn.com/wbw/001_001_003.mp3"
        )
        XCTAssertEqual(
            AyahWordAudioURL.resolve("https://verses.example.com/wbw/a.mp3")?.absoluteString,
            "https://verses.example.com/wbw/a.mp3"
        )
        XCTAssertNil(AyahWordAudioURL.resolve("http://audio.qurancdn.com/wbw/a.mp3"))
        XCTAssertNil(AyahWordAudioURL.resolve("file:///etc/passwd"))
        XCTAssertNil(AyahWordAudioURL.resolve("javascript:alert(1)"))
        XCTAssertNil(AyahWordAudioURL.resolve("ftp://audio.qurancdn.com/a.mp3"))
        XCTAssertNil(AyahWordAudioURL.resolve("wbw/../../a.mp3"))
        XCTAssertNil(AyahWordAudioURL.resolve(""))
        XCTAssertNil(AyahWordAudioURL.resolve(nil))
    }

    // MARK: - Decoding

    /// A documented-shape answer. The Arabic fields are filled with Arabic scalars through JSON escapes,
    /// so the test proves they are never read.
    private static let sampleJSON = """
    {"verse": {"id": 1, "verse_key": "1:1", "text_uthmani": "\\u0628\\u0633\\u0645",
      "words": [
        {"id": 1, "position": 1, "audio_url": "wbw/001_001_001.mp3", "char_type_name": "word",
         "text_uthmani": "\\u0628\\u0633\\u0645", "text": "\\u0628\\u0633\\u0645", "code_v1": "\\u0628",
         "location": "1:1:1",
         "translation": {"text": "Meaning one", "language_name": "english"},
         "transliteration": {"text": "word-one", "language_name": "english"}},
        {"id": 2, "position": 2, "audio_url": null, "char_type_name": "word",
         "text_uthmani": "\\u0627\\u0644\\u0644\\u0647",
         "translation": {"text": "  Meaning two  "},
         "transliteration": {"text": null}},
        {"id": 3, "position": "3", "char_type_name": "WORD",
         "translation": {"text": "Meaning three"}},
        {"id": 4, "position": 4, "audio_url": null, "char_type_name": "end",
         "text_uthmani": "\\u0661",
         "translation": {"text": "(1)"}}
      ]}}
    """

    func testDecodingDropsEndAndIgnoresArabicFields() throws {
        let response = try RelayClient.makeDecoder().decode(AyahWordsResponse.self, from: Data(Self.sampleJSON.utf8))
        let entries = response.entries
        XCTAssertEqual(entries.map(\.position), [1, 2, 3])
        XCTAssertEqual(entries.map(\.meaning), ["Meaning one", "Meaning two", "Meaning three"])
        XCTAssertEqual(entries.map(\.transliteration), ["word-one", nil, nil])
        XCTAssertEqual(entries[0].audioURL?.absoluteString, "https://audio.qurancdn.com/wbw/001_001_001.mp3")
        XCTAssertNil(entries[1].audioURL)
        XCTAssertNil(entries[2].audioURL)
        for entry in entries {
            XCTAssertFalse(Self.containsArabicScalar(entry.meaning))
            XCTAssertFalse(Self.containsArabicScalar(entry.transliteration))
            XCTAssertFalse(Self.containsArabicScalar(entry.audioURL?.absoluteString))
        }
    }

    func testDecodingIsLenient() throws {
        let json = """
        {"verse": {"words": [{"position": "x", "translation": "not an object"}, {"char_type_name": "word"}]}}
        """
        let response = try RelayClient.makeDecoder().decode(AyahWordsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.entries.map(\.position), [1, 2])
        XCTAssertTrue(response.entries.allSatisfy { $0.meaning == nil && $0.audioURL == nil })

        let noVerse = try RelayClient.makeDecoder().decode(AyahWordsResponse.self, from: Data("{}".utf8))
        XCTAssertTrue(noVerse.entries.isEmpty)
    }

    // MARK: - Relay provider

    func testRelayProviderUsesDocumentedPath() async throws {
        let relay = WordsFakeRelay()
        let path = RelayAyahWordsProvider.path(sura: 1, ayah: 1)
        XCTAssertEqual(path, "/api/v4/verses/by_key/1:1?words=true&language=en&word_fields=location")
        XCTAssertNoThrow(try RelayClient.url(base: URL(string: "https://relay.example.com")!, relativePath: path))
        relay.serve(path, json: Self.sampleJSON)

        let provider = RelayAyahWordsProvider(client: relay)
        let entries = try await provider.words(sura: 1, ayah: 1)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(relay.requested, [path])
    }

    func testRelayProviderErrors() async {
        let relay = WordsFakeRelay()
        let provider = RelayAyahWordsProvider(client: relay)

        do {
            _ = try await provider.words(sura: 2, ayah: 255)
            XCTFail("Expected offline")
        } catch {
            XCTAssertEqual(error as? RelayError, .transport)
        }

        relay.serve(RelayAyahWordsProvider.path(sura: 1, ayah: 2), json: #"{"verse": {"words": []}}"#)
        do {
            _ = try await provider.words(sura: 1, ayah: 2)
            XCTFail("Expected empty")
        } catch {
            XCTAssertEqual(error as? AyahWordsError, .empty)
        }

        do {
            _ = try await provider.words(sura: 115, ayah: 1)
            XCTFail("Expected invalid")
        } catch {
            XCTAssertEqual(error as? AyahWordsError, .invalidAyah)
        }
        XCTAssertEqual(relay.requested, [
            RelayAyahWordsProvider.path(sura: 2, ayah: 255),
            RelayAyahWordsProvider.path(sura: 1, ayah: 2),
        ])
    }

    // MARK: - Fake provider and factory

    func testFakeProviderHasNoArabicAndFollowsTheCount() async throws {
        let fake = FakeAyahWordsProvider(wordCount: { _, _ in 5 })
        let first = try await fake.words(sura: 1, ayah: 3)
        XCTAssertEqual(first.map(\.position), [1, 2, 3, 4, 5])
        XCTAssertTrue(first.allSatisfy { $0.transliteration != nil && $0.audioURL != nil })
        XCTAssertEqual(first[0].audioURL?.absoluteString, "https://audio.qurancdn.com/wbw/001_003_001.mp3")

        let other = try await fake.words(sura: 2, ayah: 1)
        XCTAssertEqual(other.count, 3)
        XCTAssertTrue(other.allSatisfy { $0.transliteration == nil && $0.audioURL == nil && $0.meaning != nil })

        for entry in first + other {
            XCTAssertFalse(Self.containsArabicScalar(entry.meaning))
            XCTAssertFalse(Self.containsArabicScalar(entry.transliteration))
        }
    }

    func testFakeProviderLinesUpWithEveryAyahOfTheOpening() async throws {
        let data = try QuranBundle.load()
        let fake = FakeAyahWordsProvider()
        for ayah in data.ayahs(inSura: 1) {
            let entries = try await fake.words(sura: 1, ayah: ayah.number)
            let result = AyahWordsBuilder.rows(storedText: ayah.displayText, entries: entries)
            XCTAssertTrue(result.aligned, "Ayah \(ayah.number) did not line up")
            XCTAssertTrue(result.rows.allSatisfy { $0.arabic != nil })
        }
    }

    func testFactoryGivesNoProviderInsideTests() {
        XCTAssertNil(AyahWordsProviderFactory.live())
    }

    @MainActor
    func testErrorMessagesArePlain() {
        XCTAssertEqual(AyahWordsSheet.message(for: RelayError.transport), "No connection. Try again when you are online.")
        XCTAssertEqual(AyahWordsSheet.message(for: AyahWordsError.empty), "The words could not be loaded. Try again.")
        XCTAssertEqual(AyahWordsSheet.message(for: RelayError.server(status: 503)), "The words could not be loaded. Try again.")
    }
}
