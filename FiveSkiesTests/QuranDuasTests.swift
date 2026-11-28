import XCTest
@testable import FiveSkies

/// Duas from the Quran: a manifest of keys and titles only, checked against the bundled text.
final class QuranDuasTests: XCTestCase {
    func testEveryKeyIsARealAyahAndAppearsOnce() throws {
        let data = try QuranBundle.load()
        let refs = QuranDuas.entries.map(\.ref)
        XCTAssertEqual(refs.count, 5)
        XCTAssertEqual(Set(refs).count, refs.count)
        for ref in refs {
            let ayah = try XCTUnwrap(data.ayah(ref), "\(ref.sura):\(ref.aya) is not in the bundled text")
            // Whole ayah: none of these is an ayah 1, so the shown text is the stored text.
            XCTAssertEqual(ayah.displayText, ayah.text)
        }
    }

    func testTitlesArePlainEnglish() {
        for entry in QuranDuas.entries {
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.title.contains("\u{2014}"))
            XCTAssertTrue(entry.title.unicodeScalars.allSatisfy { $0.isASCII }, entry.title)
        }
    }
}
