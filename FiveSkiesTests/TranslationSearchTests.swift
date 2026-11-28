import XCTest
@testable import FiveSkies

/// Search in the meaning (E2.3). Only made up English sentences are used.
final class TranslationSearchTests: XCTestCase {
    private func ids(_ hits: [TranslationSearchHit]) -> [String] {
        hits.map(\.id)
    }

    private func matched(_ hit: TranslationSearchHit) -> String {
        let characters = Array(hit.snippet)
        XCTAssertGreaterThanOrEqual(hit.matchRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(hit.matchRange.upperBound, characters.count)
        guard hit.matchRange.lowerBound >= 0, hit.matchRange.upperBound <= characters.count else { return "" }
        return String(characters[hit.matchRange])
    }

    /// Forty made up words with "lantern" placed after `position` of them.
    private func longLine(lanternAfter position: Int) -> String {
        var words = (1...40).map { "word\($0)" }
        words.insert("lantern", at: position)
        return words.joined(separator: " ")
    }

    // MARK: - Matching

    func testEveryWordMustAppear() {
        let verses = [
            "1:1": "The river runs past the old mill",
            "1:2": "A lamp glows beside the river",
            "1:3": "A lamp sits on the shelf"
        ]
        XCTAssertEqual(ids(TranslationSearch.search("river lamp", in: verses)), ["1:2"])
        XCTAssertEqual(ids(TranslationSearch.search("lamp", in: verses)), ["1:2", "1:3"])
        XCTAssertEqual(ids(TranslationSearch.search("lamp mill", in: verses)), [])
    }

    func testCaseAndDiacriticFolding() {
        let verses = [
            "3:1": "A quiet caf\u{E9} by the water",
            "3:2": "Another CAFE opened",
            "3:3": "The cafe\u{301} at noon",
            "3:4": "Nothing to see here"
        ]
        XCTAssertEqual(ids(TranslationSearch.search("Caf\u{E9}", in: verses)), ["3:1", "3:2", "3:3"])
        XCTAssertEqual(ids(TranslationSearch.search("cafe", in: verses)), ["3:1", "3:2", "3:3"])
        XCTAssertEqual(ids(TranslationSearch.search("WATER", in: verses)), ["3:1"])

        let hits = TranslationSearch.search("cafe", in: verses)
        XCTAssertEqual(hits.count, 3)
        guard hits.count == 3 else { return }
        XCTAssertEqual(hits[0].snippet, "A quiet caf\u{E9} by the water")
        XCTAssertEqual(hits[0].matchRange, 8..<12)
        XCTAssertEqual(matched(hits[0]), "caf\u{E9}")
        XCTAssertEqual(matched(hits[1]), "CAFE")
        XCTAssertEqual(hits[2].matchRange, 4..<8)
        XCTAssertEqual(matched(hits[2]), "cafe\u{301}")
    }

    func testCurlyApostropheMatchesStraightOne() {
        let verses = ["4:1": "The traveller\u{2019}s bag was light"]
        XCTAssertEqual(ids(TranslationSearch.search("traveller's", in: verses)), ["4:1"])
    }

    func testMatchInsideAWord() {
        let hits = TranslationSearch.search("amp", in: ["5:1": "The lamps were lit"])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first.map(matched), "amp")
        XCTAssertEqual(hits.first?.matchRange, 5..<8)
    }

    // MARK: - Order, limits and keys

    func testResultsAreInQuranOrderByNumber() {
        let verses = [
            "2:10": "A lantern in the hall",
            "2:9": "A lantern by the door",
            "10:1": "A lantern on the hill",
            "1:7": "A lantern in the yard",
            "2:100": "A lantern at the gate"
        ]
        XCTAssertEqual(ids(TranslationSearch.search("lantern", in: verses)), ["1:7", "2:9", "2:10", "2:100", "10:1"])
    }

    func testLimitKeepsTheFirstInOrder() {
        var verses: [String: String] = [:]
        for aya in 1...60 {
            verses["1:\(aya)"] = "Line \(aya) has a lantern"
        }
        XCTAssertEqual(TranslationSearch.search("lantern", in: verses).count, 50)
        XCTAssertEqual(ids(TranslationSearch.search("lantern", in: verses, limit: 3)), ["1:1", "1:2", "1:3"])
        XCTAssertEqual(TranslationSearch.search("lantern", in: verses, limit: 0), [])

        let index = TranslationSearchIndex(verses: verses)
        XCTAssertEqual(index.entries.count, 60)
        XCTAssertEqual(index.search("lantern", limit: 7), TranslationSearch.search("lantern", in: verses, limit: 7))
    }

    func testShortQueryReturnsNothing() {
        let verses = ["1:1": "A lamp glows"]
        XCTAssertEqual(TranslationSearch.search("", in: verses), [])
        XCTAssertEqual(TranslationSearch.search("   ", in: verses), [])
        XCTAssertEqual(TranslationSearch.search("la", in: verses), [])
        XCTAssertEqual(TranslationSearch.search("  la  ", in: verses), [])
        XCTAssertEqual(ids(TranslationSearch.search("  lam  ", in: verses)), ["1:1"])
        XCTAssertNil(TranslationSearch.queryWords("ab"))
        XCTAssertEqual(TranslationSearch.queryWords("Lamp  lamp RIVER"), ["lamp", "river"])
    }

    func testBadKeysAreIgnored() {
        let verses = [
            "x:1": "A lantern",
            "2": "A lantern",
            "2:3:4": "A lantern",
            "0:5": "A lantern",
            "4:": "A lantern",
            ":4": "A lantern",
            "4:-1": "A lantern",
            " 4:1": "A lantern",
            "5:2": "A lantern"
        ]
        XCTAssertEqual(ids(TranslationSearch.search("lantern", in: verses)), ["5:2"])
        XCTAssertEqual(TranslationSearchIndex(verses: verses).entries.count, 1)
        XCTAssertNil(TranslationSearch.parseKey("2:x"))
        XCTAssertEqual(TranslationSearch.parseKey("2:255")?.sura, 2)
        XCTAssertEqual(TranslationSearch.parseKey("2:255")?.aya, 255)
    }

    // MARK: - Snippets

    func testShortVerseIsShownWhole() {
        let text = "The bright lamp stood on the table"
        let hits = TranslationSearch.search("LAMP", in: ["6:1": text])
        XCTAssertEqual(hits.count, 1)
        guard let hit = hits.first else { return }
        XCTAssertEqual(hit.snippet, text)
        XCTAssertEqual(hit.matchRange, 11..<15)
        XCTAssertEqual(matched(hit), "lamp")
    }

    func testLongVerseIsCutOnWordsAroundTheMatch() {
        let text = longLine(lanternAfter: 20)
        XCTAssertGreaterThan(text.count, 200)
        let hits = TranslationSearch.search("lantern", in: ["7:1": text])
        XCTAssertEqual(hits.count, 1)
        guard let hit = hits.first else { return }

        XCTAssertTrue(hit.snippet.hasPrefix("\u{2026}"))
        XCTAssertTrue(hit.snippet.hasSuffix("\u{2026}"))
        XCTAssertLessThanOrEqual(hit.snippet.count, 130)
        XCTAssertGreaterThanOrEqual(hit.snippet.count, 100)
        XCTAssertEqual(matched(hit), "lantern")

        let inner = String(hit.snippet.dropFirst().dropLast())
        XCTAssertFalse(inner.hasPrefix(" "))
        XCTAssertFalse(inner.hasSuffix(" "))
        guard let found = text.range(of: inner) else {
            return XCTFail("The snippet must be a piece of the verse")
        }
        XCTAssertNotEqual(found.lowerBound, text.startIndex)
        XCTAssertEqual(text[text.index(before: found.lowerBound)], " ")
        XCTAssertNotEqual(found.upperBound, text.endIndex)
        XCTAssertEqual(text[found.upperBound], " ")
    }

    func testMatchNearTheStartKeepsTheStart() {
        let text = longLine(lanternAfter: 1)
        let hit = TranslationSearch.search("lantern", in: ["7:2": text]).first
        XCTAssertEqual(hit?.snippet.hasPrefix("word1 lantern"), true)
        XCTAssertEqual(hit?.snippet.hasSuffix("\u{2026}"), true)
        XCTAssertEqual(hit?.matchRange, 6..<13)
        XCTAssertEqual(hit.map(matched), "lantern")
    }

    func testMatchAtTheEndKeepsTheEnd() {
        let text = longLine(lanternAfter: 40)
        let hit = TranslationSearch.search("lantern", in: ["7:3": text]).first
        XCTAssertEqual(hit?.snippet.hasPrefix("\u{2026}"), true)
        XCTAssertEqual(hit?.snippet.hasSuffix("word40 lantern"), true)
        XCTAssertEqual(hit.map(matched), "lantern")
    }

    func testSnippetUsesTheEarliestMatchingWord() {
        let text = longLine(lanternAfter: 30) + " meadow"
        let hit = TranslationSearch.search("meadow word3", in: ["7:4": text]).first
        // "word3" first appears at the start, well before "meadow".
        XCTAssertEqual(hit?.snippet.hasPrefix("word1 word2 word3"), true)
        XCTAssertEqual(hit.map(matched), "word3")
    }

    func testAttributedSnippetStylesOnlyTheMatch() {
        let hit = TranslationSearch.search("lamp", in: ["6:1": "The bright lamp stood on the table"]).first
        XCTAssertNotNil(hit)
        guard let hit else { return }
        let attributed = TranslationSearch.attributedSnippet(hit)
        XCTAssertEqual(String(attributed.characters), hit.snippet)
        let bold = attributed.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        XCTAssertEqual(bold.count, 1)
        XCTAssertEqual(bold.first.map { String(attributed[$0.range].characters) }, "lamp")
    }

    func testTitleUsesTheSurahName() {
        let hit = TranslationSearchHit(sura: 2, aya: 255, snippet: "text", matchRange: 0..<4)
        XCTAssertEqual(TranslationSearch.title(for: hit, suraName: "Al-Baqara"), "Al-Baqara 2:255")
        XCTAssertEqual(TranslationSearch.title(for: hit, suraName: nil), "2:255")
        XCTAssertEqual(hit.target, QuranReaderTarget(sura: 2, aya: 255))
    }
}
