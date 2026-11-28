import XCTest
@testable import FiveSkies

/// Round E3, plan L4: common words counted from the stored text. Test strings are built from
/// code points; no Arabic in source.
final class CommonWordsTests: XCTestCase {
    // MARK: - Synthetic text

    private static func scalar(_ value: UInt32) -> String {
        String(UnicodeScalar(value)!)
    }

    /// Letter, fatha, letter.
    private static func word(_ first: UInt32, _ second: UInt32) -> String {
        scalar(first) + scalar(0x064E) + scalar(second)
    }

    private static let wordA = word(0x0628, 0x0627)
    private static let wordB = word(0x0645, 0x0646)
    private static let wordC = word(0x0644, 0x0647)
    private static let wordD = word(0x0633, 0x0645)
    private static let wordE = word(0x0646, 0x0628)
    /// A small high pause mark (a non-spacing mark): a sign-only token.
    private static let pauseSign = scalar(0x06D6)
    /// The rub el hizb sign: a sign-only token that can start an ayah.
    private static let rubElHizb = scalar(0x06DE)

    private static func line(_ tokens: [String]) -> String {
        tokens.joined(separator: " ")
    }

    private static let english = Locale(identifier: "en_US")

    /// Suras of ayah texts, sura 1 first.
    private func makeData(_ suras: [[String]]) -> QuranData {
        var first = 0
        var suraList: [Sura] = []
        var ayahs: [[Ayah]] = []
        for (offset, texts) in suras.enumerated() {
            let number = offset + 1
            suraList.append(
                Sura(
                    number: number,
                    arabicName: "",
                    transliteratedName: "Test \(number)",
                    englishName: "Test",
                    revelation: .meccan,
                    ayahCount: texts.count,
                    firstAyahIndex: first
                )
            )
            ayahs.append(texts.enumerated().map { Ayah(sura: number, number: $0.offset + 1, text: $0.element) })
            first += texts.count
        }
        let start = AyahRef(sura: 1, aya: 1)
        return QuranData(suras: suraList, ayahsBySura: ayahs, juzStarts: [start], pageStarts: [start], sajdas: [])
    }

    private func entry(_ index: CommonWordsIndex, _ form: String) -> CommonWordEntry? {
        index.entries.first { $0.form == form }
    }

    // MARK: - Counting

    func testCountsExactFormsAndTotals() throws {
        let data = makeData([[
            Self.line([Self.wordA, Self.wordB, Self.wordA]),
            Self.line([Self.wordB, Self.wordC]),
        ]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.totalWordCount, 5)
        XCTAssertEqual(index.distinctFormCount, 3)
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordA)).count, 2)
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordB)).count, 2)
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordC)).count, 1)
        XCTAssertEqual(index.entries.map(\.rank), [1, 2, 3])
        XCTAssertEqual(index.entries.reduce(0) { $0 + $1.count }, index.totalWordCount)
    }

    func testHigherCountRanksFirst() {
        let data = makeData([[Self.line([Self.wordA, Self.wordB, Self.wordB])]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.entries.map(\.form), [Self.wordB, Self.wordA])
        XCTAssertEqual(index.entries.map(\.count), [2, 1])
    }

    func testTiesKeepQuranOrderOfFirstOccurrence() {
        // C and A both appear twice; C comes first in the text, so C ranks first.
        let data = makeData([
            [Self.line([Self.wordC, Self.wordA]), Self.line([Self.wordA, Self.wordC])],
            [Self.line([Self.wordE, Self.wordD])],
        ])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.entries.map(\.form), [Self.wordC, Self.wordA, Self.wordE, Self.wordD])
        // Building twice gives the same order.
        XCTAssertEqual(CommonWordsIndex(data: data).entries, index.entries)
    }

    func testFirstOccurrenceIsSuraAyahAndOneBasedWordPosition() throws {
        let data = makeData([
            [Self.line([Self.wordA, Self.wordB]), Self.line([Self.wordC, Self.wordD, Self.wordB])],
            [Self.line([Self.wordE, Self.wordC]), Self.line([Self.wordD, Self.wordE])],
        ])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordB)).firstOccurrence, CommonWordOccurrence(sura: 1, aya: 1, wordPosition: 2))
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordD)).firstOccurrence, CommonWordOccurrence(sura: 1, aya: 2, wordPosition: 2))
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordE)).firstOccurrence, CommonWordOccurrence(sura: 2, aya: 1, wordPosition: 1))
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordE)).firstOccurrence.ref, AyahRef(sura: 2, aya: 1))
    }

    func testFirstOccurrenceDoesNotDependOnInputOrder() throws {
        let data = makeData([
            [Self.line([Self.wordA, Self.wordB]), Self.line([Self.wordB, Self.wordA])],
        ])
        let reversed = CommonWordsIndex(ayahs: data.ayahsBySura.joined().reversed())
        XCTAssertEqual(try XCTUnwrap(entry(reversed, Self.wordB)).firstOccurrence, CommonWordOccurrence(sura: 1, aya: 1, wordPosition: 2))
        XCTAssertEqual(reversed.entries.map(\.form), [Self.wordA, Self.wordB])
    }

    // MARK: - Splitter rules

    func testSignOnlyTokenJoinsTheWordBeforeIt() throws {
        // "B sign" is one word, exactly as the splitter slices it, and a different form from "B".
        let data = makeData([[
            Self.line([Self.wordA, Self.wordB, Self.pauseSign, Self.wordC]),
            Self.line([Self.wordB]),
        ]])
        let index = CommonWordsIndex(data: data)
        let joined = Self.wordB + " " + Self.pauseSign
        XCTAssertEqual(index.totalWordCount, 4)
        XCTAssertEqual(index.distinctFormCount, 4)
        let signed = try XCTUnwrap(entry(index, joined))
        XCTAssertEqual(signed.count, 1)
        XCTAssertEqual(signed.firstOccurrence, CommonWordOccurrence(sura: 1, aya: 1, wordPosition: 2))
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordB)).firstOccurrence, CommonWordOccurrence(sura: 1, aya: 2, wordPosition: 1))
        // Word C keeps position 3: the sign is not a word.
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordC)).firstOccurrence.wordPosition, 3)
    }

    func testLeadingSignIsNotCounted() throws {
        let data = makeData([[Self.line([Self.rubElHizb, Self.wordA, Self.wordB])]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.totalWordCount, 2)
        XCTAssertEqual(index.entries.map(\.form), [Self.wordA, Self.wordB])
        XCTAssertEqual(try XCTUnwrap(entry(index, Self.wordA)).firstOccurrence.wordPosition, 1)
    }

    func testFormsAreExactSlicesOfTheStoredString() {
        let stored = Self.line([Self.wordA, Self.wordB, Self.pauseSign, Self.wordC])
        let index = CommonWordsIndex(data: makeData([[stored]]))
        let ranges = AyahWordSplitter.wordRanges(in: stored)
        let slices = ranges.map { Array(stored.unicodeScalars[$0]) }
        let forms = index.entries.sorted { $0.firstOccurrence < $1.firstOccurrence }.map { Array($0.form.unicodeScalars) }
        XCTAssertEqual(forms, slices)
    }

    func testBasmalaHeaderIsNotCounted() {
        // Ayah 1 of sura 2: the first four words are the header, only the rest is the ayah's displayText.
        let first = Self.line([Self.wordA, Self.wordA, Self.wordA, Self.wordA, Self.wordE])
        let data = makeData([[Self.wordB], [first]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.totalWordCount, 2)
        XCTAssertNil(entry(index, Self.wordA))
        XCTAssertEqual(entry(index, Self.wordE)?.firstOccurrence, CommonWordOccurrence(sura: 2, aya: 1, wordPosition: 1))
    }

    // MARK: - Coverage

    func testCoverageArithmetic() {
        // A 3 times, B 2 times, C once: 6 words.
        let data = makeData([[
            Self.line([Self.wordA, Self.wordB, Self.wordA]),
            Self.line([Self.wordC, Self.wordB, Self.wordA]),
        ]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(index.entries.map(\.count), [3, 2, 1])
        XCTAssertEqual(index.coveredWordCount(top: 0), 0)
        XCTAssertEqual(index.coveredWordCount(top: 1), 3)
        XCTAssertEqual(index.coveredWordCount(top: 2), 5)
        XCTAssertEqual(index.coveredWordCount(top: 99), 6)
        XCTAssertEqual(index.coveredWordCount(top: -4), 0)
        XCTAssertEqual(index.coverage(top: 1), 0.5, accuracy: 1e-12)
        XCTAssertEqual(index.coverage(top: 2), 5.0 / 6.0, accuracy: 1e-12)
        XCTAssertEqual(index.coverage(top: 3), 1, accuracy: 1e-12)
        XCTAssertEqual(index.coveragePercent(top: 1), 50)
        XCTAssertEqual(index.coveragePercent(top: 2), 83)
        XCTAssertEqual(index.coveragePercent(top: 500), 100)
        XCTAssertEqual(index.top(2).map(\.rank), [1, 2])
        XCTAssertEqual(index.top(50).count, 3)
    }

    func testEmptyTextGivesZeroCoverage() {
        let index = CommonWordsIndex(data: makeData([[Self.pauseSign]]))
        XCTAssertEqual(index.totalWordCount, 0)
        XCTAssertEqual(index.distinctFormCount, 0)
        XCTAssertEqual(index.coverage(top: 100), 0)
        XCTAssertEqual(index.coveragePercent(top: 100), 0)
    }

    // MARK: - Text

    func testHeadlineUsesComputedNumbers() {
        let data = makeData([[
            Self.line([Self.wordA, Self.wordB, Self.wordA]),
            Self.line([Self.wordC, Self.wordB, Self.wordA]),
        ]])
        let index = CommonWordsIndex(data: data)
        XCTAssertEqual(
            CommonWordsText.headline(index: index, top: 2, locale: Self.english),
            "These 2 words make up 83% of all the words in the Quran"
        )
        // More than there are: the headline names how many there really are.
        XCTAssertEqual(
            CommonWordsText.headline(index: index, top: 100, locale: Self.english),
            "These 3 words make up 100% of all the words in the Quran"
        )
        XCTAssertEqual(CommonWordsText.totals(index: index, locale: Self.english), "6 words in all, in 3 written forms")
    }

    func testCountAndExampleLines() {
        XCTAssertEqual(CommonWordsText.appears(1, locale: Self.english), "appears 1 time")
        XCTAssertEqual(CommonWordsText.appears(1098, locale: Self.english), "appears 1,098 times")
        XCTAssertEqual(
            CommonWordsText.example(suraName: "Al-Test", occurrence: CommonWordOccurrence(sura: 2, aya: 5, wordPosition: 3)),
            "Al-Test 2:5, word 3"
        )
        XCTAssertEqual(CommonWordsText.choices, [50, 100, 200, 500])
        XCTAssertFalse(CommonWordsText.note.contains("\u{2014}"))
    }

    // MARK: - Meaning lookup

    private func entries(_ positions: [Int]) -> [AyahWordEntry] {
        positions.map {
            AyahWordEntry(position: $0, meaning: "Meaning \($0)", transliteration: "word-\($0)", audioURL: nil)
        }
    }

    func testMeaningComesFromTheAlignedRowAtThePosition() throws {
        let stored = Self.line([Self.wordA, Self.wordB, Self.pauseSign, Self.wordC])
        let row = try XCTUnwrap(
            CommonWordMeaning.lookup(storedText: stored, entries: entries([1, 2, 3]), wordPosition: 2, form: Self.wordB + " " + Self.pauseSign)
        )
        XCTAssertEqual(row.meaning, "Meaning 2")
        XCTAssertEqual(row.transliteration, "word-2")
    }

    func testMeaningIsWithheldWhenTheAyahDoesNotLineUp() {
        let stored = Self.line([Self.wordA, Self.wordB, Self.wordC])
        XCTAssertNil(CommonWordMeaning.lookup(storedText: stored, entries: entries([1, 2]), wordPosition: 2, form: Self.wordB))
        XCTAssertNil(CommonWordMeaning.lookup(storedText: stored, entries: entries([1, 2, 4]), wordPosition: 2, form: Self.wordB))
        XCTAssertNil(CommonWordMeaning.lookup(storedText: stored, entries: [], wordPosition: 1, form: Self.wordA))
        // Aligned, but the slice at that position is not this form.
        XCTAssertNil(CommonWordMeaning.lookup(storedText: stored, entries: entries([1, 2, 3]), wordPosition: 2, form: Self.wordC))
        // No such word.
        XCTAssertNil(CommonWordMeaning.lookup(storedText: stored, entries: entries([1, 2, 3]), wordPosition: 4, form: Self.wordC))
    }

    // MARK: - Bundled text

    func testBundledTextBuildsAStableIndex() throws {
        let data = try QuranBundle.load()
        let index = CommonWordsIndex(data: data)
        XCTAssertGreaterThan(index.totalWordCount, 70_000)
        XCTAssertEqual(index.entries.reduce(0) { $0 + $1.count }, index.totalWordCount)
        XCTAssertEqual(index.entries.first?.rank, 1)
        for (earlier, later) in zip(index.entries, index.entries.dropFirst()) {
            XCTAssertTrue(
                earlier.count > later.count
                    || (earlier.count == later.count && earlier.firstOccurrence < later.firstOccurrence)
            )
        }
        let coverage = [50, 100, 200, 500].map { index.coverage(top: $0) }
        XCTAssertEqual(coverage, coverage.sorted())
    }
}
