import XCTest
@testable import FiveSkies

final class GlossaryTests: XCTestCase {
    /// ASCII letters, space, hyphen and apostrophe: Latin letters only, no other script.
    private func isLatinTitle(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || scalar == " " || scalar == "-" || scalar == "'"
        }
    }

    func testEveryTermHasTitleAndMeaning() {
        for term in GlossaryTerm.allCases {
            XCTAssertFalse(term.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(term) has no title")
            XCTAssertFalse(term.meaning.trimmingCharacters(in: .whitespaces).isEmpty, "\(term) has no meaning")
        }
    }

    func testTitlesAreUnique() {
        let titles = GlossaryTerm.allCases.map { $0.title.lowercased() }
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testTitlesUseLatinLettersOnly() {
        for term in GlossaryTerm.allCases {
            XCTAssertTrue(isLatinTitle(term.title), "\(term) title is not Latin letters only")
        }
    }

    func testMeaningsArePlainASCII() {
        for term in GlossaryTerm.allCases {
            XCTAssertTrue(term.meaning.unicodeScalars.allSatisfy { $0.isASCII }, "\(term) meaning has a non-ASCII character")
        }
    }

    func testNoEmDashMustOrMissed() {
        let emDash = "\u{2014}"
        let enDash = "\u{2013}"
        for term in GlossaryTerm.allCases {
            for text in [term.title, term.meaning] {
                XCTAssertFalse(text.contains(emDash), "\(term) has an em dash")
                XCTAssertFalse(text.contains(enDash), "\(term) has an en dash")
                XCTAssertFalse(text.lowercased().contains("must"), "\(term) says must")
                XCTAssertFalse(text.lowercased().contains("missed"), "\(term) says missed")
            }
        }
    }

    func testMeaningsAreShort() {
        for term in GlossaryTerm.allCases {
            XCTAssertLessThanOrEqual(term.meaning.count, 160, "\(term) meaning is longer than two short lines")
        }
    }

    func testRequiredTermsArePresent() {
        let titles = Set(GlossaryTerm.allCases.map { $0.title })
        let required = [
            "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha", "Jumu'ah", "Qibla", "Adhan", "Wudu",
            "Rakah", "Sunnah", "Surah", "Ayah", "Juz", "Page", "Hijri", "Ramadan", "Eid", "Dhikr",
            "Tasbih", "Dua", "Zakat", "Basmala", "Tafsir", "Transliteration", "Reciter", "Tahajjud",
            "Duha", "Day of Arafah"
        ]
        for title in required {
            XCTAssertTrue(titles.contains(title), "\(title) is missing")
        }
    }

    func testEveryPrayerMapsToItsTerm() {
        for prayer in Prayer.allCases {
            let term = GlossaryTerm(prayer)
            XCTAssertEqual(term.rawValue, prayer.rawValue)
            XCTAssertEqual(term.title, prayer.displayName)
        }
    }

    func testDayRowIDs() {
        XCTAssertEqual(GlossaryTerm(dayRowID: "sunrise"), .sunrise)
        XCTAssertEqual(GlossaryTerm(dayRowID: "duha"), .duha)
        XCTAssertEqual(GlossaryTerm(dayRowID: "lastThird"), .lastThird)
        XCTAssertEqual(GlossaryTerm(dayRowID: "suhurEnds"), .suhur)
        XCTAssertEqual(GlossaryTerm(dayRowID: "isha"), .isha)
        XCTAssertNil(GlossaryTerm(dayRowID: "discouraged-zenith"))
    }

    func testAlphabeticalOrderAndSections() {
        let titles = GlossaryTerm.alphabetical.map { $0.title.lowercased() }
        XCTAssertEqual(titles, titles.sorted())
        XCTAssertEqual(GlossaryTerm.alphabetical.count, GlossaryTerm.allCases.count)

        let sections = GlossaryTerm.sections(matching: "")
        XCTAssertEqual(sections.flatMap(\.terms).count, GlossaryTerm.allCases.count)
        XCTAssertEqual(Set(sections.map(\.letter)).count, sections.count, "a letter appears twice")
        for section in sections {
            for term in section.terms {
                XCTAssertEqual(String(term.title.prefix(1)).uppercased(), section.letter)
            }
        }
    }

    func testSearchMatchesTitleAndMeaning() {
        XCTAssertEqual(GlossaryTerm.matching("qibla").first, .qibla)
        XCTAssertTrue(GlossaryTerm.matching("dawn").contains(.fajr))
        XCTAssertTrue(GlossaryTerm.matching("  ").count == GlossaryTerm.allCases.count)
        XCTAssertTrue(GlossaryTerm.matching("zzzz").isEmpty)
        XCTAssertTrue(GlossaryTerm.sections(matching: "zzzz").isEmpty)
    }
}
