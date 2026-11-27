import XCTest
@testable import FiveSkies

// Round C1 timing builder tests. No Arabic is typed here: test strings are built at run time
// from Unicode scalar values, and every JSON answer uses numbers and made-up fields only.

/// A relay that answers from canned JSON by exact relative path and counts requests.
/// Unknown paths act as offline.
private final class TimingTestRelay: RelayFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Result<Data, Error>] = [:]
    private var log: [String] = []

    func serve(_ path: String, json: String) {
        lock.withLock { answers[path] = .success(Data(json.utf8)) }
    }

    func fail(_ path: String, with error: Error) {
        lock.withLock { answers[path] = .failure(error) }
    }

    var requested: [String] {
        lock.withLock { log }
    }

    func data(relativePath: String) async throws -> Data {
        let result: Result<Data, Error>? = lock.withLock {
            log.append(relativePath)
            return answers[relativePath]
        }
        guard let result else { throw RelayError.transport }
        return try result.get()
    }
}

/// Scalar values used to build test strings.
private enum TS {
    static let beh: UInt32 = 0x0628
    static let seen: UInt32 = 0x0633
    static let meem: UInt32 = 0x0645
    static let fatha: UInt32 = 0x064E
    static let pauseMark: UInt32 = 0x06D6
    static let rubElHizb: UInt32 = 0x06DE
    static let sajdah: UInt32 = 0x06E9
    static let tatweel: UInt32 = 0x0640
    static let digitOne: UInt32 = 0x0661
    static let space: UInt32 = 0x20

    /// A string made of these scalars, in order.
    static func string(_ values: [UInt32]) -> String {
        var view = String.UnicodeScalarView()
        for value in values {
            guard let scalar = Unicode.Scalar(value) else {
                XCTFail("Bad scalar \(value)")
                continue
            }
            view.append(scalar)
        }
        return String(view)
    }

    /// Words of scalars joined by single spaces.
    static func words(_ tokens: [[UInt32]]) -> String {
        var values: [UInt32] = []
        for (index, token) in tokens.enumerated() {
            if index > 0 { values.append(space) }
            values.append(contentsOf: token)
        }
        return string(values)
    }

    static let wordA: [UInt32] = [beh, fatha, seen]
    static let wordB: [UInt32] = [seen, meem, fatha]
    static let wordC: [UInt32] = [meem]
    static let wordD: [UInt32] = [beh, meem]

    static func scalars(_ text: String, _ range: Range<String.Index>) -> [UInt32] {
        text.unicodeScalars[range].map(\.value)
    }
}

final class ListenTimingTests: XCTestCase {

    // MARK: - W2 splitter

    func testLetterClassesUseScalarProperties() {
        XCTAssertTrue(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.beh)!))
        XCTAssertTrue(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.meem)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.fatha)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.pauseMark)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.rubElHizb)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.sajdah)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.tatweel)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(TS.digitOne)!))
        XCTAssertFalse(AyahWordSplitter.isArabicLetter("A"))
        // A letter of another script (Hebrew alef) is not an Arabic letter.
        XCTAssertFalse(AyahWordSplitter.isArabicLetter(Unicode.Scalar(0x05D0)!))
        XCTAssertTrue(AyahWordSplitter.isSeparator(" "))
        XCTAssertFalse(AyahWordSplitter.isSeparator(Unicode.Scalar(TS.beh)!))
    }

    func testSplitsOnSpacesAndRangesIndexTheOriginalString() {
        let text = TS.words([TS.wordA, TS.wordB, TS.wordC])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(TS.scalars(text, ranges[0]), TS.wordA)
        XCTAssertEqual(TS.scalars(text, ranges[1]), TS.wordB)
        XCTAssertEqual(TS.scalars(text, ranges[2]), TS.wordC)
        XCTAssertEqual(ranges[0].lowerBound, text.startIndex)
        XCTAssertEqual(ranges[2].upperBound, text.endIndex)
        XCTAssertEqual(String(text[ranges[1]]), TS.string(TS.wordB))
        // In order, never overlapping, and the string itself is untouched.
        for pair in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.upperBound, pair.1.lowerBound)
        }
        XCTAssertEqual(text, TS.words([TS.wordA, TS.wordB, TS.wordC]))
    }

    func testPauseMarkAttachesToTheWordBefore() {
        // word, space, pause mark (its own token), space, word
        let text = TS.words([TS.wordA, [TS.pauseMark], TS.wordB])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TS.scalars(text, ranges[0]), TS.wordA + [TS.space, TS.pauseMark])
        XCTAssertEqual(TS.scalars(text, ranges[1]), TS.wordB)
    }

    func testSajdahSignAtTheEndAttachesToTheLastWord() {
        let text = TS.words([TS.wordA, TS.wordB, [TS.sajdah]])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[1].upperBound, text.endIndex)
        XCTAssertEqual(TS.scalars(text, ranges[1]), TS.wordB + [TS.space, TS.sajdah])
    }

    func testSeveralSignsInARowAllAttach() {
        let text = TS.words([TS.wordA, [TS.pauseMark], [TS.sajdah], TS.wordB])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TS.scalars(text, ranges[0]), TS.wordA + [TS.space, TS.pauseMark, TS.space, TS.sajdah])
    }

    func testLeadingSignBelongsToNoWord() {
        let text = TS.words([[TS.rubElHizb], TS.wordA, TS.wordB])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TS.scalars(text, ranges[0]), TS.wordA)
        XCTAssertGreaterThan(ranges[0].lowerBound, text.startIndex)
    }

    func testTokensWithoutALetterAreNotWords() {
        // Marks only, a digit, a tatweel: none of them is a word.
        let text = TS.words([TS.wordA, [TS.fatha], [TS.digitOne], [TS.tatweel]])
        XCTAssertEqual(AyahWordSplitter.wordCount(in: text), 1)
        XCTAssertEqual(AyahWordSplitter.wordRanges(in: text).first?.upperBound, text.endIndex)
    }

    func testEmptyAndSpacingEdgeCases() {
        XCTAssertEqual(AyahWordSplitter.wordRanges(in: ""), [])
        XCTAssertEqual(AyahWordSplitter.wordRanges(in: "   "), [])
        XCTAssertEqual(AyahWordSplitter.wordRanges(in: TS.string([TS.pauseMark])), [])
        // Double and trailing spaces do not make empty words.
        let text = TS.string(TS.wordA + [TS.space, TS.space] + TS.wordB + [TS.space])
        let ranges = AyahWordSplitter.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(TS.scalars(text, ranges[1]), TS.wordB)
        XCTAssertLessThan(ranges[1].upperBound, text.endIndex)
    }

    func testScalarOffsetsMatchTheRanges() {
        let ayah = Ayah(sura: 1, number: 2, text: TS.words([TS.wordA, TS.wordB]))
        let followText = FollowAlongText(ayah: ayah)
        XCTAssertEqual(followText.wordCount, 2)
        XCTAssertEqual(followText.scalarOffsets(of: followText.wordRanges[0]), 0..<3)
        XCTAssertEqual(followText.scalarOffsets(of: followText.wordRanges[1]), 4..<7)
        XCTAssertEqual(followText.range(ofWord: 2), followText.wordRanges[1])
        XCTAssertNil(followText.range(ofWord: 0))
        XCTAssertNil(followText.range(ofWord: 3))
    }

    // MARK: - Basmala (W5)

    func testFirstAyahWithBasmalaUsesTheTextTheReaderShows() {
        let basmalaWords = [TS.wordA, TS.wordB, TS.wordC, TS.wordD]
        let stored = TS.words(basmalaWords + [TS.wordB, TS.wordA])
        let ayah = Ayah(sura: 2, number: 1, text: stored)
        let followText = FollowAlongText(ayah: ayah)
        XCTAssertTrue(followText.hasBasmalaHeader)
        XCTAssertEqual(followText.text, ayah.displayText)
        XCTAssertEqual(followText.wordCount, 2)
        XCTAssertEqual(TS.scalars(followText.text, followText.wordRanges[0]), TS.wordB)
        // The stored ayah is untouched.
        XCTAssertEqual(ayah.text, stored)
    }

    func testFatihahAndTawbahKeepTheWholeFirstAyah() {
        let stored = TS.words([TS.wordA, TS.wordB, TS.wordC, TS.wordD, TS.wordA])
        let fatihah = FollowAlongText(ayah: Ayah(sura: 1, number: 1, text: stored))
        XCTAssertFalse(fatihah.hasBasmalaHeader)
        XCTAssertEqual(fatihah.text, stored)
        XCTAssertEqual(fatihah.wordCount, 5)
        let tawbah = FollowAlongText(ayah: Ayah(sura: 9, number: 1, text: stored))
        XCTAssertFalse(tawbah.hasBasmalaHeader)
        XCTAssertEqual(tawbah.wordCount, 5)
        let laterAyah = FollowAlongText(ayah: Ayah(sura: 2, number: 2, text: stored))
        XCTAssertFalse(laterAyah.hasBasmalaHeader)
        XCTAssertEqual(laterAyah.wordCount, 5)
    }

    // MARK: - W3 alignment

    private func timing(ayah: Int, positions: [Int]) -> AyahTiming {
        let words = positions.enumerated().map { offset, position in
            WordTiming(position: position, start: Double(offset), end: Double(offset) + 0.5)
        }
        return AyahTiming(ayah: ayah, start: 0, end: Double(max(1, positions.count)), words: words)
    }

    private func threeWordText(ayah: Int = 3) -> FollowAlongText {
        FollowAlongText(ayah: Ayah(sura: 1, number: ayah, text: TS.words([TS.wordA, TS.wordB, TS.wordC])))
    }

    func testEqualCountsMapWordByWord() {
        let text = threeWordText()
        let result = TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [1, 2, 3]))
        XCTAssertEqual(result.alignment, .words(text.wordRanges))
        XCTAssertNil(result.fallback)
    }

    func testAWordHeardTwiceCountsOnce() {
        let text = threeWordText()
        let result = TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [1, 2, 2, 3]))
        XCTAssertTrue(result.alignment.isWordLevel)
    }

    func testDifferentCountsFallBackToAyahLevel() {
        let text = threeWordText()
        let more = TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [1, 2, 3, 4]))
        XCTAssertEqual(more.alignment, .ayahOnly)
        XCTAssertEqual(more.fallback, .countMismatch)
        let fewer = TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [1, 2]))
        XCTAssertEqual(fewer.fallback, .countMismatch)
    }

    func testGapsAndMissingTimingsFallBack() {
        let text = threeWordText()
        XCTAssertEqual(TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [1, 2, 4])).fallback, .positionGap)
        XCTAssertEqual(TimingAlignment.evaluate(text, timing: timing(ayah: 3, positions: [])).fallback, .noWordTimings)
        XCTAssertEqual(TimingAlignment.evaluate(text, timing: nil).fallback, .noTiming)
        XCTAssertEqual(TimingAlignment.align(text, timing: nil), .ayahOnly)
    }

    func testSurahFollowAlongCountsFallbacks() {
        let ayahs = [
            Ayah(sura: 1, number: 1, text: TS.words([TS.wordA, TS.wordB])),
            Ayah(sura: 1, number: 2, text: TS.words([TS.wordA, TS.wordB, TS.wordC])),
            Ayah(sura: 1, number: 3, text: TS.words([TS.wordA])),
        ]
        let timings = SurahTimings(reciterID: 6, chapter: 1, ayahs: [
            timing(ayah: 1, positions: [1, 2]),
            timing(ayah: 2, positions: [1, 2]),
        ])
        let followAlong = SurahFollowAlong(chapter: 1, ayahs: ayahs, timings: timings)
        XCTAssertEqual(followAlong.reciterID, 6)
        XCTAssertEqual(followAlong.ayahsChecked, 3)
        XCTAssertEqual(followAlong.ayahsFallingBack, 2)
        XCTAssertTrue(followAlong.alignment(forAyah: 1).isWordLevel)
        XCTAssertEqual(followAlong.fallbackReason(forAyah: 2), .countMismatch)
        XCTAssertEqual(followAlong.fallbackReason(forAyah: 3), .noTiming)
        XCTAssertEqual(followAlong.fallbackAyahs.map { $0.ayah }, [2, 3])

        // Timings for another chapter are ignored.
        let other = SurahFollowAlong(chapter: 2, ayahs: ayahs, timings: timings)
        XCTAssertEqual(other.ayahsChecked, 0)
        XCTAssertNil(other.reciterID)
    }

    // MARK: - FollowAlongState

    func testHighlightFollowsThePlayer() throws {
        let ayahs = [
            Ayah(sura: 1, number: 1, text: TS.words([TS.wordA, TS.wordB])),
            Ayah(sura: 1, number: 2, text: TS.words([TS.wordA, TS.wordB, TS.wordC])),
        ]
        let timings = SurahTimings(reciterID: 6, chapter: 1, ayahs: [
            timing(ayah: 1, positions: [1, 2]),
            timing(ayah: 2, positions: [1, 2, 3, 4]),
        ])
        let followAlong = SurahFollowAlong(chapter: 1, ayahs: ayahs, timings: timings)
        let firstText = try XCTUnwrap(followAlong.text(forAyah: 1))

        XCTAssertEqual(
            FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: 1, currentWord: 2, followAlong: followAlong),
            .word(ayah: 1, range: firstText.wordRanges[1])
        )
        XCTAssertEqual(
            FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: 1, currentWord: nil, followAlong: followAlong),
            .betweenWords(ayah: 1)
        )
        XCTAssertEqual(
            FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: 1, currentWord: 9, followAlong: followAlong),
            .betweenWords(ayah: 1)
        )
        // Ayah 2 does not line up, so it highlights whole whatever the word.
        XCTAssertEqual(
            FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: 2, currentWord: 1, followAlong: followAlong),
            .wholeAyah(ayah: 2)
        )
        XCTAssertNil(FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: nil, currentWord: nil, followAlong: followAlong))
        XCTAssertNil(FollowAlongState.highlight(readerChapter: 1, playingChapter: 2, currentAyah: 1, currentWord: 1, followAlong: followAlong))
        XCTAssertNil(FollowAlongState.highlight(readerChapter: 1, playingChapter: nil, currentAyah: 1, currentWord: 1, followAlong: followAlong))
        XCTAssertEqual(
            FollowAlongState.highlight(readerChapter: 1, playingChapter: 1, currentAyah: 1, currentWord: 1, followAlong: nil),
            .wholeAyah(ayah: 1)
        )
        XCTAssertEqual(FollowAlongHighlight.word(ayah: 4, range: firstText.wordRanges[0]).ayah, 4)
    }

    // MARK: - Decoding

    private static func path(_ reciter: Int, _ chapter: Int) -> String {
        "/api/v4/chapter_recitations/\(reciter)/\(chapter)?segments=true"
    }

    // Shaped like the documented answer, cut down to two ayahs.
    private static let documentedJSON = """
    {
      "audio_file": {
        "id": 457,
        "chapter_id": 1,
        "file_size": 710784,
        "format": "mp3",
        "audio_url": "https://example.com/1.mp3",
        "timestamps": [
          {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 6493, "duration": -6493,
           "segments": [[1, 0, 630], [2, 650, 1570], [3, 1570, 3110], [4, 3110, 5590]]},
          {"verse_key": "1:2", "timestamp_from": 6493, "timestamp_to": 11546, "duration": -5053,
           "segments": [[1, 6493, 7243], [2, 7243, 8123]]}
        ]
      }
    }
    """

    func testPathAsksForSegments() {
        XCTAssertEqual(RelayTimingProvider.path(reciterID: 7, chapter: 1), "/api/v4/chapter_recitations/7/1?segments=true")
    }

    func testDecodesTheDocumentedShapeInSeconds() async throws {
        let relay = TimingTestRelay()
        relay.serve(Self.path(7, 1), json: Self.documentedJSON)
        let provider = RelayTimingProvider(client: relay)
        let loaded = await provider.timings(reciterID: 7, chapter: 1)
        let timings = try XCTUnwrap(loaded)
        XCTAssertEqual(timings.reciterID, 7)
        XCTAssertEqual(timings.chapter, 1)
        XCTAssertEqual(timings.ayahs.map(\.ayah), [1, 2])
        XCTAssertEqual(timings.ayahs[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(timings.ayahs[0].end, 6.493, accuracy: 0.0001)
        XCTAssertEqual(timings.ayahs[0].words.count, 4)
        XCTAssertEqual(timings.ayahs[0].words[1].position, 2)
        XCTAssertEqual(timings.ayahs[0].words[1].start, 0.65, accuracy: 0.0001)
        XCTAssertEqual(timings.ayahs[0].words[1].end, 1.57, accuracy: 0.0001)
        XCTAssertEqual(timings.ayahs[1].words.count, 2)
        XCTAssertEqual(relay.requested, [Self.path(7, 1)])
    }

    func testVerseKeyParsing() {
        XCTAssertEqual(ChapterTimingResponse.ayahNumber(verseKey: "1:1", chapter: 1), 1)
        XCTAssertEqual(ChapterTimingResponse.ayahNumber(verseKey: " 2:286 ", chapter: 2), 286)
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "2:1", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "1:0", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "1:-3", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "1:x", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "1-3", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "1:2:3", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: ":3", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: "", chapter: 1))
        XCTAssertNil(ChapterTimingResponse.ayahNumber(verseKey: nil, chapter: 1))
    }

    func testBadEntriesAndSegmentsAreDropped() throws {
        let json = """
        {
          "audio_file": {
            "chapter_id": "3",
            "timestamps": [
              "not an object",
              {"verse_key": "3:1", "timestamp_from": "1000", "timestamp_to": 5000,
               "segments": [
                 [1, 1000, 2000],
                 ["2", "2000", "3000"],
                 [3, 3000],
                 [3, 3000, 4000, 9],
                 [4, "x", 4500],
                 [null, 1, 2],
                 {"position": 5},
                 "text",
                 [0, 100, 200],
                 [1.5, 100, 200],
                 [6, 4500, 4400],
                 [7, -10, 20],
                 []
               ]},
              {"verse_key": "3:2", "timestamp_from": 5000, "segments": [[1, 5000, 6000]]},
              {"verse_key": "3:3", "timestamp_from": 7000, "timestamp_to": 6000},
              {"verse_key": "4:4", "timestamp_from": 8000, "timestamp_to": 9000},
              {"verse_key": "3:5", "timestamp_from": 9000, "timestamp_to": 10000, "segments": null},
              {"verse_key": "3:5", "timestamp_from": 1, "timestamp_to": 2},
              {"verse_key": "3:6", "timestamp_from": 10000, "timestamp_to": 11000, "segments": "bad",
               "future_field": {"a": [1, 2]}}
            ]
          }
        }
        """
        let response = try RelayClient.makeDecoder().decode(ChapterTimingResponse.self, from: Data(json.utf8))
        let timings = try XCTUnwrap(response.surahTimings(reciterID: 12, chapter: 3))
        XCTAssertEqual(timings.ayahs.map(\.ayah), [1, 5, 6])
        let first = timings.ayahs[0]
        XCTAssertEqual(first.start, 1, accuracy: 0.0001)
        XCTAssertEqual(first.words.map(\.position), [1, 2])
        XCTAssertEqual(first.words[1].start, 2, accuracy: 0.0001)
        // The first copy of a repeated ayah wins.
        XCTAssertEqual(timings.ayahs[1].start, 9, accuracy: 0.0001)
        XCTAssertEqual(timings.ayahs[1].words, [])
        XCTAssertEqual(timings.ayahs[2].words, [])
    }

    func testWordsAreSortedByStart() throws {
        let json = """
        {"audio_file": {"chapter_id": 1, "timestamps": [
          {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 3000,
           "segments": [[2, 1000, 2000], [1, 0, 900]]}
        ]}}
        """
        let response = try RelayClient.makeDecoder().decode(ChapterTimingResponse.self, from: Data(json.utf8))
        let timings = try XCTUnwrap(response.surahTimings(reciterID: 1, chapter: 1))
        XCTAssertEqual(timings.ayahs[0].words.map(\.position), [1, 2])
    }

    // MARK: - Provider

    func testOtherChapterFileOrNoTimestampsGiveNil() async {
        let relay = TimingTestRelay()
        relay.serve(Self.path(7, 2), json: Self.documentedJSON)
        relay.serve(Self.path(7, 3), json: #"{"audio_file": {"chapter_id": 3, "timestamps": []}}"#)
        relay.serve(Self.path(7, 4), json: #"{"audio_file": {"chapter_id": 4}}"#)
        relay.serve(Self.path(7, 5), json: #"{"unexpected": true}"#)
        relay.serve(Self.path(7, 6), json: "not json")
        let provider = RelayTimingProvider(client: relay)
        let second = await provider.timings(reciterID: 7, chapter: 2)
        let third = await provider.timings(reciterID: 7, chapter: 3)
        let fourth = await provider.timings(reciterID: 7, chapter: 4)
        let fifth = await provider.timings(reciterID: 7, chapter: 5)
        let sixth = await provider.timings(reciterID: 7, chapter: 6)
        XCTAssertNil(second)
        XCTAssertNil(third)
        XCTAssertNil(fourth)
        XCTAssertNil(fifth)
        XCTAssertNil(sixth)
    }

    func testFailuresGiveNilAndAreNotCached() async {
        let relay = TimingTestRelay()
        relay.fail(Self.path(7, 1), with: RelayError.server(status: 503))
        let provider = RelayTimingProvider(client: relay)
        let first = await provider.timings(reciterID: 7, chapter: 1)
        XCTAssertNil(first)
        relay.serve(Self.path(7, 1), json: Self.documentedJSON)
        let second = await provider.timings(reciterID: 7, chapter: 1)
        XCTAssertNotNil(second)
        XCTAssertEqual(relay.requested.count, 2)
    }

    func testBadArgumentsNeverReachTheRelay() async {
        let relay = TimingTestRelay()
        let provider = RelayTimingProvider(client: relay)
        let zeroReciter = await provider.timings(reciterID: 0, chapter: 1)
        let noChapter = await provider.timings(reciterID: 7, chapter: 0)
        let pastEnd = await provider.timings(reciterID: 7, chapter: 115)
        XCTAssertNil(zeroReciter)
        XCTAssertNil(noChapter)
        XCTAssertNil(pastEnd)
        XCTAssertEqual(relay.requested, [])
    }

    private static func singleAyahJSON(chapter: Int) -> String {
        """
        {"audio_file": {"chapter_id": \(chapter), "timestamps": [
          {"verse_key": "\(chapter):1", "timestamp_from": 0, "timestamp_to": 1000, "segments": [[1, 0, 900]]}
        ]}}
        """
    }

    func testCacheKeepsTheLastTenSurahs() async {
        let relay = TimingTestRelay()
        for chapter in 1...11 {
            relay.serve(Self.path(7, chapter), json: Self.singleAyahJSON(chapter: chapter))
        }
        let provider = RelayTimingProvider(client: relay)
        for chapter in 1...10 {
            _ = await provider.timings(reciterID: 7, chapter: chapter)
        }
        XCTAssertEqual(relay.requested.count, 10)

        // A hit makes chapter 1 the most recent, so chapter 2 is the one dropped next.
        let hit = await provider.timings(reciterID: 7, chapter: 1)
        XCTAssertEqual(hit?.chapter, 1)
        XCTAssertEqual(relay.requested.count, 10)

        _ = await provider.timings(reciterID: 7, chapter: 11)
        XCTAssertEqual(relay.requested.count, 11)
        let keys = await provider.cachedKeys()
        XCTAssertEqual(keys.count, RelayTimingProvider.cacheLimit)
        XCTAssertFalse(keys.contains(RelayTimingProvider.Key(reciterID: 7, chapter: 2)))
        XCTAssertEqual(keys.last, RelayTimingProvider.Key(reciterID: 7, chapter: 11))

        _ = await provider.timings(reciterID: 7, chapter: 1)
        XCTAssertEqual(relay.requested.count, 11)
        _ = await provider.timings(reciterID: 7, chapter: 2)
        XCTAssertEqual(relay.requested.count, 12)

        await provider.clearCache()
        let cleared = await provider.cachedKeys()
        XCTAssertEqual(cleared, [])
    }

    func testCacheIsPerReciter() async {
        let relay = TimingTestRelay()
        relay.serve(Self.path(7, 1), json: Self.singleAyahJSON(chapter: 1))
        relay.serve(Self.path(6, 1), json: Self.singleAyahJSON(chapter: 1))
        let provider = RelayTimingProvider(client: relay)
        let seven = await provider.timings(reciterID: 7, chapter: 1)
        let six = await provider.timings(reciterID: 6, chapter: 1)
        XCTAssertEqual(seven?.reciterID, 7)
        XCTAssertEqual(six?.reciterID, 6)
        XCTAssertEqual(relay.requested.count, 2)
    }

    func testFactoryGivesNoProviderInsideTests() {
        // The unit test host never touches the network.
        XCTAssertNil(SurahTimingFactory.live())
    }

    func testFakeProviderLinesUpWithEveryAyah() async throws {
        let provider = FakeSurahTimingProvider(wordCounts: { _ in [2, 3] })
        let loaded = await provider.timings(reciterID: 1, chapter: 1)
        let timings = try XCTUnwrap(loaded)
        XCTAssertEqual(timings.ayahs.map(\.ayah), [1, 2])
        XCTAssertEqual(timings.ayahs[1].words.map(\.position), [1, 2, 3])
        XCTAssertEqual(timings.ayahs.last?.end ?? 0, 65, accuracy: 0.0001)
        let prepared = ListenTimingLookup.prepared(timings, reciterID: 1, chapter: 1)
        XCTAssertEqual(prepared?.ayahs.count, 2)
        let empty = FakeSurahTimingProvider(wordCounts: { _ in nil })
        let none = await empty.timings(reciterID: 1, chapter: 1)
        XCTAssertNil(none)
    }

    // MARK: - W4 report

    #if DEBUG
    func testDebugReportCountsWithoutText() {
        let ayahs = [
            Ayah(sura: 1, number: 1, text: TS.words([TS.wordA, TS.wordB])),
            Ayah(sura: 1, number: 2, text: TS.words([TS.wordA, TS.wordB, TS.wordC])),
            Ayah(sura: 1, number: 3, text: TS.words([TS.wordA])),
            Ayah(sura: 1, number: 4, text: TS.words([TS.wordA])),
        ]
        let timings = SurahTimings(reciterID: 6, chapter: 1, ayahs: [
            timing(ayah: 1, positions: [1, 2]),
            timing(ayah: 2, positions: [1, 2]),
            timing(ayah: 3, positions: [1]),
        ])
        let check = FollowAlongDebugReport.report(timings: timings, ayahs: ayahs)
        XCTAssertEqual(check.ayahsChecked, 4)
        XCTAssertEqual(check.ayahsFallingBack, 2)
        XCTAssertEqual(check.byReason[.countMismatch], 1)
        XCTAssertEqual(check.byReason[.noTiming], 1)
        XCTAssertEqual(check.sampleKeys, ["1:2", "1:4"])
        XCTAssertEqual(check.fallbackPercent, 50, accuracy: 0.0001)

        let line = FollowAlongDebugReport.summary(check, scope: "surah 1")
        XCTAssertTrue(line.contains("4 ayahs checked"))
        XCTAssertTrue(line.contains("2 fall back"))
        // No Arabic script, so no Quran text, ever reaches the log line.
        XCTAssertFalse(ListenCatalogText.containsArabicScript(line))

        let doubled = check.adding(check)
        XCTAssertEqual(doubled.ayahsChecked, 8)
        XCTAssertEqual(doubled.byReason[.noTiming], 2)
        XCTAssertEqual(doubled.chapters, 2)
    }

    func testAuditArgument() {
        XCTAssertNil(FollowAlongDebugReport.auditReciterID(processInfo: ProcessInfo.processInfo))
    }
    #endif
}
