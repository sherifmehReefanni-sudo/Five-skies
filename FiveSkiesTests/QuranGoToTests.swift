import XCTest
@testable import FiveSkies

/// The Go to parser against the bundled Tanzil metadata. Names and numbers only, no verse text.
final class QuranGoToTests: XCTestCase {
    private static var cached: QuranData?

    private func quran() throws -> QuranData {
        if let cached = Self.cached {
            return cached
        }
        let loaded = try QuranBundle.load()
        Self.cached = loaded
        return loaded
    }

    private struct NoPlace: Error {}

    /// The one place the text goes to, or a failure.
    private func place(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> (QuranReaderTarget, String) {
        let result = QuranGoTo.parse(text, data: try quran())
        guard case .target(let found, let label) = result else {
            XCTFail("Expected one place for \"\(text)\", got \(result)", file: file, line: line)
            throw NoPlace()
        }
        return (found, label)
    }

    private func assertGoes(
        _ text: String,
        to sura: Int,
        _ aya: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let (found, _) = try place(text, file: file, line: line)
        XCTAssertEqual(found, QuranReaderTarget(sura: sura, aya: aya), "for \"\(text)\"", file: file, line: line)
    }

    private func assertNothing(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(QuranGoTo.parse(text, data: try quran()), .nothing, "for \"\(text)\"", file: file, line: line)
    }

    /// Writes digits with another script's digits, built from code points so no literal appears here.
    private func digits(_ text: String, zero: UInt32) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value >= 48, scalar.value <= 57, let mapped = Unicode.Scalar(zero + scalar.value - 48) {
                scalars.append(mapped)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // MARK: - Surah and ayah

    func testBundledSpellingOfSurahTwo() throws {
        XCTAssertEqual(try quran().sura(2)?.transliteratedName, "Al-Baqara")
    }

    func testSurahAndAyahForms() throws {
        for text in ["2:255", "2 255", "2.255", " 2 : 255 ", "2,255", "2/255", "Surah 2:255", "sura 2 255", "00002:0255"] {
            try assertGoes(text, to: 2, 255)
        }
        let (_, label) = try place("2:255")
        XCTAssertEqual(label, "Al-Baqara, ayah 255")
    }

    func testSurahNumberAlone() throws {
        try assertGoes("2", to: 2, nil)
        try assertGoes("surah 2", to: 2, nil)
        try assertGoes("SURAH 36", to: 36, nil)
        try assertGoes("Surat 114", to: 114, nil)
        try assertGoes("s2", to: 2, nil)
        try assertGoes("1", to: 1, nil)
        let (_, label) = try place("surah 2")
        XCTAssertEqual(label, "Surah 2, Al-Baqara")
    }

    func testUnicodeDigitsAreNormalised() throws {
        // Arabic-Indic, extended Arabic-Indic and full width digits.
        for zero: UInt32 in [0x0660, 0x06F0, 0xFF10] {
            try assertGoes(digits("2:255", zero: zero), to: 2, 255)
            try assertGoes(digits("page 50", zero: zero), to: 3, 1)
            try assertGoes(digits("juz 30", zero: zero), to: 78, 1)
        }
    }

    // MARK: - Names

    func testSurahNamesWithSpellingDifferences() throws {
        let cases: [(String, Int)] = [
            ("baqara", 2), ("Baqara", 2), ("al-baqarah", 2), ("Al Baqarah", 2), ("albaqara", 2), ("bakara", 2),
            ("fatiha", 1), ("Al-Fatihah", 1), ("faatiha", 1),
            ("yasin", 36), ("ya sin", 36), ("Ya-Sin", 36), ("Yaseen", 36),
            ("kahf", 18), ("al kahf", 18), ("Al-Kahf", 18),
            ("rahman", 55), ("ar-rahman", 55), ("arrahman", 55),
            ("al imran", 3), ("imran", 3), ("aal imran", 3),
            ("anam", 6), ("al-an'am", 6), ("an\u{2019}aam", 6),
            ("nas", 114), ("an-nas", 114), ("annas", 114),
            ("quraysh", 106), ("layl", 92), ("duha", 93), ("taha", 20), ("nuh", 71), ("mulk", 67), ("ikhlas", 112)
        ]
        for (text, sura) in cases {
            try assertGoes(text, to: sura, nil)
        }
    }

    func testEnglishMeanings() throws {
        try assertGoes("the cow", to: 2, nil)
        try assertGoes("The Cow", to: 2, nil)
        try assertGoes("cow", to: 2, nil)
        try assertGoes("the opening", to: 1, nil)
        try assertGoes("joseph", to: 12, nil)
        try assertGoes("the cave", to: 18, nil)
    }

    func testNameWithAyah() throws {
        try assertGoes("baqara 255", to: 2, 255)
        try assertGoes("al-kahf:10", to: 18, 10)
        try assertGoes("yasin 1", to: 36, 1)
    }

    func testNameTiesGiveSuggestionsInSurahOrder() throws {
        // Al-Fajr and Al-Falaq are both "The Dawn" in the metadata.
        for text in ["the dawn", "Dawn"] {
            guard case .suggestions(let suggestions) = QuranGoTo.parse(text, data: try quran()) else {
                return XCTFail("Expected suggestions for \"\(text)\"")
            }
            XCTAssertEqual(suggestions.map(\.target.sura), [89, 113], "for \"\(text)\"")
            XCTAssertEqual(suggestions.first?.title, "Al-Fajr")
            XCTAssertNil(suggestions.first?.target.aya)
        }
        guard case .suggestions(let withAyah) = QuranGoTo.parse("the dawn 20", data: try quran()) else {
            return XCTFail("Expected suggestions for a tie with an ayah")
        }
        // Al-Falaq has 5 ayahs, so its suggestion is clamped.
        XCTAssertEqual(withAyah.map(\.target), [QuranReaderTarget(sura: 89, aya: 20), QuranReaderTarget(sura: 113, aya: 5)])
    }

    func testExactNameBeatsPrefixMatches() throws {
        // "nas" is exactly An-Naas and only the start of An-Nasr.
        try assertGoes("nas", to: 114, nil)
        try assertGoes("fajr", to: 89, nil)
        try assertGoes("falaq", to: 113, nil)
    }

    func testShortPrefixesGiveAtMostSixSuggestions() throws {
        guard case .suggestions(let suggestions) = QuranGoTo.parse("al", data: try quran()) else {
            return XCTFail("Expected suggestions for a bare article")
        }
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertLessThanOrEqual(suggestions.count, QuranGoTo.maxSuggestions)
        XCTAssertEqual(Set(suggestions.map(\.id)).count, suggestions.count)
    }

    // MARK: - Pages and juz

    func testPageForms() throws {
        let data = try quran()
        let start = data.pageStarts[49]
        for text in ["page 50", "Page 50", "p50", "P 50", "pg 50", "page50"] {
            try assertGoes(text, to: start.sura, start.aya)
        }
        XCTAssertEqual(start, AyahRef(sura: 3, aya: 1))
        try assertGoes("page 1", to: 1, 1)
        let last = data.pageStarts[603]
        try assertGoes("page 604", to: last.sura, last.aya)
        let (_, label) = try place("page 50")
        XCTAssertEqual(label, "Page 50, Aal-i-Imraan, ayah 1")
    }

    func testJuzForms() throws {
        let data = try quran()
        for text in ["juz 30", "Juz 30", "j30", "J 30", "juz' 30", "para 30"] {
            try assertGoes(text, to: 78, 1)
        }
        for (offset, start) in data.juzStarts.enumerated() {
            try assertGoes("juz \(offset + 1)", to: start.sura, start.aya)
        }
        let (_, label) = try place("juz 30")
        XCTAssertEqual(label, "Juz 30, An-Naba, ayah 1")
    }

    // MARK: - Clamping

    func testAyahPastTheEndGoesToTheLastAyah() throws {
        let (found, label) = try place("2:300")
        XCTAssertEqual(found, QuranReaderTarget(sura: 2, aya: 286))
        XCTAssertEqual(label, "Al-Baqara has 286 ayahs. Going to ayah 286.")
        try assertGoes("1:8", to: 1, 7)
        try assertGoes("114 999999", to: 114, 6)
        try assertGoes("yasin 100", to: 36, 83)
        let (_, lastLabel) = try place("2:286")
        XCTAssertEqual(lastLabel, "Al-Baqara, ayah 286")
    }

    // MARK: - Nonsense

    func testImpossibleInputGivesNothing() throws {
        let cases = [
            "", "   ", "::", "a", "qwrtpz", "zzzzqq",
            "0", "115", "surah 0", "surah 115", "2:0", "0:1", "2:255:1", "2 baqara",
            "page", "page 0", "page 605", "p", "juz", "juz 0", "juz 31", "j", "surah",
            "2:1234567", "page 99999999999999999999"
        ]
        for text in cases {
            try assertNothing(text)
        }
    }

    func testGoTakesTheBestSuggestion() {
        let first = QuranGoToSuggestion(target: QuranReaderTarget(sura: 89, aya: nil), title: "Al-Fajr", detail: "")
        let second = QuranGoToSuggestion(target: QuranReaderTarget(sura: 113, aya: nil), title: "Al-Falaq", detail: "")
        XCTAssertEqual(QuranGoToResult.suggestions([first, second]).destination, first.target)
        XCTAssertEqual(
            QuranGoToResult.target(QuranReaderTarget(sura: 2, aya: 255), label: "x").destination,
            QuranReaderTarget(sura: 2, aya: 255)
        )
        XCTAssertNil(QuranGoToResult.nothing.destination)
    }

    // MARK: - Shared keys and the sura list search

    func testNameKeys() {
        XCTAssertEqual(QuranNameKey.squash("yaseen"), "yasin")
        XCTAssertEqual(QuranNameKey.squash("baqarah"), "baqara")
        XCTAssertTrue(QuranNameKey.keys("Al-Baqara").contains("baqara"))
        XCTAssertTrue(QuranNameKey.keys("ya sin").contains("yasin"))
        XCTAssertEqual(QuranNameKey.tokens("p50"), ["p", "50"])
        XCTAssertEqual(QuranNameKey.tokens("Juz' 30"), ["juz", "30"])
        XCTAssertEqual(QuranNameKey.editDistance("bakara", "baqara", limit: 2), 1)
    }

    func testSuraListSearchForgivesSpelling() throws {
        let data = try quran()
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "baqarah").map(\.number).contains(2))
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "yasin").map(\.number).contains(36))
        XCTAssertEqual(QuranSearch.filter(data.suras, query: "18").map(\.number), [18])
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "zzzzqq").isEmpty)
    }
}
