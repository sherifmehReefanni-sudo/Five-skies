import XCTest
@testable import FiveSkies

/// Checks the bundled Tanzil files parse exactly. No verse text appears in these tests or their messages.
final class QuranParserTests: XCTestCase {
    private static var cached: QuranData?

    private func quran() throws -> QuranData {
        if let cached = Self.cached {
            return cached
        }
        let loaded = try QuranBundle.load()
        Self.cached = loaded
        return loaded
    }

    private func bundledFile(_ name: String, _ ext: String) throws -> URL {
        let url = QuranBundle.resourceBundle().url(forResource: name, withExtension: ext)
        return try XCTUnwrap(url, "\(name).\(ext) is not in the app bundle")
    }

    // MARK: - Counts

    func testThereAre114SurasAnd6236Ayahs() throws {
        let data = try quran()
        XCTAssertEqual(data.suras.count, 114)
        XCTAssertEqual(data.ayahsBySura.count, 114)
        XCTAssertEqual(data.ayahCount, 6236)
    }

    func testEverySuraAyahCountMatchesTheMetadata() throws {
        let data = try quran()
        let metadata = try QuranParser.parseMetadata(Data(contentsOf: bundledFile("quran-data", "xml")))
        XCTAssertEqual(metadata.suras.count, 114)
        for entry in metadata.suras {
            XCTAssertEqual(data.ayahs(inSura: entry.index).count, entry.ayahCount, "Sura \(entry.index)")
            XCTAssertEqual(data.sura(entry.index)?.ayahCount, entry.ayahCount, "Sura \(entry.index)")
        }
    }

    func testAyahNumbersRunFromOneWithNoGaps() throws {
        let data = try quran()
        for sura in data.suras {
            let numbers = data.ayahs(inSura: sura.number).map(\.number)
            XCTAssertEqual(numbers, Array(1...sura.ayahCount), "Sura \(sura.number)")
            XCTAssertTrue(data.ayahs(inSura: sura.number).allSatisfy { $0.sura == sura.number })
        }
    }

    func testSuraMetadataIsFilledIn() throws {
        let data = try quran()
        for sura in data.suras {
            XCTAssertFalse(sura.arabicName.isEmpty, "Sura \(sura.number)")
            XCTAssertFalse(sura.transliteratedName.isEmpty, "Sura \(sura.number)")
            XCTAssertFalse(sura.englishName.isEmpty, "Sura \(sura.number)")
        }
        XCTAssertEqual(data.sura(18)?.transliteratedName, "Al-Kahf")
    }

    // MARK: - Basmala

    func testBasmalaIsSplitForEverySuraExceptOneAndNine() throws {
        let data = try quran()
        for sura in data.suras where sura.number != 1 && sura.number != 9 {
            let first = try XCTUnwrap(data.ayahs(inSura: sura.number).first)
            let basmala = try XCTUnwrap(first.basmala, "Sura \(sura.number) has no basmala")
            XCTAssertEqual(basmala.split(separator: " ", omittingEmptySubsequences: false).count, 4, "Sura \(sura.number)")
            XCTAssertFalse(first.displayText.isEmpty, "Sura \(sura.number)")
            XCTAssertEqual(
                Array((basmala + " " + first.displayText).utf8),
                Array(first.text.utf8),
                "Sura \(sura.number): the split does not rebuild the stored text"
            )
            for later in data.ayahs(inSura: sura.number).dropFirst() {
                XCTAssertNil(later.basmala)
                XCTAssertEqual(later.displayText, later.text)
            }
        }
    }

    func testSurasOneAndNineHaveNoSeparateBasmala() throws {
        let data = try quran()
        for number in [1, 9] {
            for ayah in data.ayahs(inSura: number) {
                XCTAssertNil(ayah.basmala, "Sura \(number) ayah \(ayah.number)")
                XCTAssertEqual(Array(ayah.displayText.utf8), Array(ayah.text.utf8), "Sura \(number) ayah \(ayah.number)")
            }
        }
    }

    func testBasmalaSplitOnPlaceholderText() {
        let split = Ayah(sura: 2, number: 1, text: "w1 w2 w3 w4 rest of it")
        XCTAssertEqual(split.basmala, "w1 w2 w3 w4")
        XCTAssertEqual(split.displayText, "rest of it")
        XCTAssertEqual(split.text, "w1 w2 w3 w4 rest of it")

        let opening = Ayah(sura: 1, number: 1, text: "w1 w2 w3 w4")
        XCTAssertNil(opening.basmala)
        XCTAssertEqual(opening.displayText, "w1 w2 w3 w4")

        let repentance = Ayah(sura: 9, number: 1, text: "w1 w2 w3 w4 w5")
        XCTAssertNil(repentance.basmala)
        XCTAssertEqual(repentance.displayText, "w1 w2 w3 w4 w5")

        let second = Ayah(sura: 2, number: 2, text: "w1 w2 w3 w4 w5")
        XCTAssertNil(second.basmala)

        let tooShort = Ayah(sura: 3, number: 1, text: "w1 w2 w3 w4")
        XCTAssertNil(tooShort.basmala)
        XCTAssertEqual(tooShort.displayText, "w1 w2 w3 w4")
    }

    // MARK: - Exact text

    func testStoredTextRoundTripsByteForByte() throws {
        let data = try quran()
        let bytes = [UInt8](try Data(contentsOf: bundledFile("quran-uthmani", "txt")))
        var expected: [[UInt8]] = []
        for line in bytes.split(separator: 0x0A, omittingEmptySubsequences: false) {
            guard let firstByte = line.first, firstByte != UInt8(ascii: "#") else { continue }
            let bars = line.indices.filter { line[$0] == UInt8(ascii: "|") }
            XCTAssertGreaterThanOrEqual(bars.count, 2)
            guard bars.count >= 2 else { continue }
            expected.append(Array(line[(bars[1] + 1)...]))
        }
        XCTAssertEqual(expected.count, 6236)

        let ayahs = data.ayahsBySura.flatMap { $0 }
        XCTAssertEqual(ayahs.count, expected.count)
        var mismatches: [String] = []
        for (ayah, stored) in zip(ayahs, expected) {
            XCTAssertFalse(ayah.text.isEmpty, "\(ayah.sura):\(ayah.number) is empty")
            if Array(ayah.text.utf8) != stored {
                mismatches.append("\(ayah.sura):\(ayah.number)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "Text differs from the file at \(mismatches.prefix(5).joined(separator: ", "))")
    }

    // MARK: - Pages, juz and sajdas

    func testPageLookup() throws {
        let data = try quran()
        XCTAssertEqual(data.page(for: AyahRef(sura: 1, aya: 1)), 1)
        XCTAssertEqual(data.page(for: AyahRef(sura: 114, aya: 6)), 604)
        XCTAssertEqual(data.page(for: AyahRef(sura: 2, aya: 1)), 2)
        XCTAssertEqual(data.pageStarts.count, 604)
        XCTAssertEqual(data.pageStarting(at: AyahRef(sura: 1, aya: 1)), 1)
        XCTAssertNil(data.page(for: AyahRef(sura: 114, aya: 7)))
        XCTAssertNil(data.page(for: AyahRef(sura: 115, aya: 1)))
    }

    func testJuzLookup() throws {
        let data = try quran()
        XCTAssertEqual(data.juz(for: AyahRef(sura: 1, aya: 1)), 1)
        XCTAssertEqual(data.juz(for: AyahRef(sura: 114, aya: 6)), 30)
        XCTAssertEqual(data.juzStarts.count, 30)
        for (offset, start) in data.juzStarts.enumerated() {
            XCTAssertEqual(data.juz(for: start), offset + 1)
            XCTAssertEqual(data.juzStarting(at: start), offset + 1)
        }
    }

    func testThereAre15Sajdas() throws {
        let data = try quran()
        XCTAssertEqual(data.sajdas.count, 15)
        for sajda in data.sajdas {
            XCTAssertNotNil(data.sajda(at: sajda.ref))
            XCTAssertNotNil(data.ayah(sajda.ref))
        }
    }

    // MARK: - Errors

    func testMalformedLinesAreRejected() {
        XCTAssertThrowsError(try QuranParser.parseText("1|1|abc\n1|2\n")) { error in
            XCTAssertEqual(error as? QuranParserError, .malformedTextLine(line: 2))
        }
        XCTAssertThrowsError(try QuranParser.parseText("x|1|abc\n"))
    }

    func testTextIsSplitOnTheFirstTwoBarsOnly() throws {
        let lines = try QuranParser.parseText("2|5|a|b c\n\n# license line\n")
        XCTAssertEqual(lines, [QuranTextLine(sura: 2, aya: 5, text: "a|b c")])
    }

    func testWrongCountsAreRejected() throws {
        let metadata = try QuranParser.parseMetadata(Data(contentsOf: bundledFile("quran-data", "xml")))
        let text = try String(contentsOf: bundledFile("quran-uthmani", "txt"), encoding: .utf8)
        let lines = try QuranParser.parseText(text)
        XCTAssertEqual(lines.count, 6236)

        XCTAssertThrowsError(try QuranParser.assemble(lines: Array(lines.dropLast()), metadata: metadata)) { error in
            XCTAssertEqual(error as? QuranParserError, .wrongAyahCount(expected: 6236, found: 6235))
        }

        var shuffled = lines
        shuffled.swapAt(1, 2)
        XCTAssertThrowsError(try QuranParser.assemble(lines: shuffled, metadata: metadata)) { error in
            XCTAssertEqual(error as? QuranParserError, .ayahNumberingGap(sura: 1, expected: 2, found: 3))
        }

        let fewerSuras = QuranMetadata(
            suras: Array(metadata.suras.dropLast()),
            juzs: metadata.juzs,
            pages: metadata.pages,
            sajdas: metadata.sajdas
        )
        XCTAssertThrowsError(try QuranParser.assemble(lines: lines, metadata: fewerSuras)) { error in
            XCTAssertEqual(error as? QuranParserError, .wrongSuraCount(expected: 114, found: 113))
        }
    }

    // MARK: - Search

    func testSearchMatchesNumberNameAndMeaning() throws {
        let data = try quran()
        XCTAssertEqual(QuranSearch.filter(data.suras, query: "18").map(\.number), [18])
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "Kahf").map(\.number).contains(18))
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "al kahf").map(\.number).contains(18))
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "OPENING").map(\.number).contains(1))
        XCTAssertEqual(QuranSearch.filter(data.suras, query: "").count, 114)
        XCTAssertTrue(QuranSearch.filter(data.suras, query: "zzzzqq").isEmpty)
    }

    func testShareTextFormat() {
        let ayah = Ayah(sura: 2, number: 255, text: "placeholder")
        XCTAssertEqual(SurahReaderView.shareText(for: ayah), "placeholder\nQuran 2:255, text from tanzil.net")
    }
}
