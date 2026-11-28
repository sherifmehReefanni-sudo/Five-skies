import SwiftUI
import XCTest
@testable import FiveSkies

/// Following the recitation in the reader, "Play from this ayah" and the ayah's spoken value.
/// Placeholder English only; no scripture.
final class ReaderFollowTests: XCTestCase {
    func testFollowsOnlyThisSurahWhileOn() {
        XCTAssertEqual(ReaderFollow.target(follows: true, readerChapter: 2, playingChapter: 2, currentAyah: 5, ayahCount: 286), 5)
        XCTAssertNil(ReaderFollow.target(follows: false, readerChapter: 2, playingChapter: 2, currentAyah: 5, ayahCount: 286))
        XCTAssertNil(ReaderFollow.target(follows: true, readerChapter: 2, playingChapter: 3, currentAyah: 5, ayahCount: 286))
        XCTAssertNil(ReaderFollow.target(follows: true, readerChapter: 2, playingChapter: nil, currentAyah: 5, ayahCount: 286))
        XCTAssertNil(ReaderFollow.target(follows: true, readerChapter: 2, playingChapter: 2, currentAyah: nil, ayahCount: 286))
    }

    func testIgnoresAyahsOutsideTheSurah() {
        XCTAssertNil(ReaderFollow.target(follows: true, readerChapter: 1, playingChapter: 1, currentAyah: 8, ayahCount: 7))
        XCTAssertNil(ReaderFollow.target(follows: true, readerChapter: 1, playingChapter: 1, currentAyah: 0, ayahCount: 7))
        XCTAssertEqual(ReaderFollow.target(follows: true, readerChapter: 1, playingChapter: 1, currentAyah: 7, ayahCount: 7), 7)
    }

    func testAnchorIsInTheUpperThird() {
        XCTAssertLessThan(ReaderFollow.anchor.y, 1.0 / 3.0)
        XCTAssertGreaterThan(ReaderFollow.anchor.y, 0)
    }

    func testPlayFromTitle() {
        XCTAssertEqual(QuranListenModel.playFromAyahTitle(startsAtBeginning: false), "Play from this ayah")
        XCTAssertEqual(
            QuranListenModel.playFromAyahTitle(startsAtBeginning: true),
            "Play from this ayah (starts at the beginning for this reciter)"
        )
    }

    func testProblemKeepsTheChosenAyahForRetry() {
        let plain = ListenPlayProblem(chapter: 2, chapterName: "Surah 2", kind: .unavailable)
        XCTAssertNil(plain.fromAyah)
        let fromAyah = ListenPlayProblem(chapter: 2, chapterName: "Surah 2", kind: .unavailable, fromAyah: 5)
        XCTAssertEqual(fromAyah.fromAyah, 5)
    }

    func testAccessibilityValueOrder() {
        XCTAssertEqual(SurahReaderView.ayahAccessibilityValue(arabic: "stored", translation: nil), "stored")
        XCTAssertEqual(
            SurahReaderView.ayahAccessibilityValue(arabic: "stored", translation: "meaning"),
            "stored\nTranslation: meaning"
        )
        XCTAssertEqual(
            SurahReaderView.ayahAccessibilityValue(arabic: "stored", transliteration: "sounds", translation: "meaning"),
            "stored\nTransliteration: sounds\nTranslation: meaning"
        )
        XCTAssertEqual(
            SurahReaderView.ayahAccessibilityValue(arabic: "stored", transliteration: "", translation: nil),
            "stored"
        )
    }
}
