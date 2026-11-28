import XCTest
@testable import FiveSkies

final class StartHerePathTests: XCTestCase {
    func testManifestIsTheAgreedOrder() {
        XCTAssertEqual(StartHerePath.surahs, [1, 112, 113, 114, 111, 110, 109, 108, 107, 106, 105, 104, 103])
        XCTAssertEqual(Set(StartHerePath.surahs).count, StartHerePath.surahs.count, "A surah appears twice")
        XCTAssertTrue(StartHerePath.surahs.allSatisfy { (1...114).contains($0) })
        XCTAssertEqual(StartHerePath.surahs.first, 1)
    }

    func testNextStepIsTheFirstNotFullyKnown() {
        XCTAssertEqual(StartHerePath.nextStep(known: []), 1)
        XCTAssertEqual(StartHerePath.nextStep(known: [1]), 112)
        XCTAssertEqual(StartHerePath.nextStep(known: [1, 112, 113]), 114)
        // Knowing a later surah first does not skip an earlier step.
        XCTAssertEqual(StartHerePath.nextStep(known: [112, 113]), 1)
        XCTAssertEqual(StartHerePath.nextStep(known: [1, 113]), 112)
        // Surahs that are not on the path change nothing.
        XCTAssertEqual(StartHerePath.nextStep(known: [2, 36]), 1)
    }

    func testNextStepIsNilWhenAllKnown() {
        XCTAssertNil(StartHerePath.nextStep(known: Set(StartHerePath.surahs)))
        XCTAssertNil(StartHerePath.nextStep(known: Set(StartHerePath.surahs).union([2])))
    }

    func testCompleteAndProgressText() {
        XCTAssertFalse(StartHerePath.isComplete(known: 3, ayahCount: 7))
        XCTAssertTrue(StartHerePath.isComplete(known: 7, ayahCount: 7))
        XCTAssertFalse(StartHerePath.isComplete(known: 0, ayahCount: 0))
        XCTAssertEqual(StartHerePath.progressText(known: 3, ayahCount: 7), "3 of 7 ayahs known")
        XCTAssertEqual(StartHerePath.progressText(known: 0, ayahCount: 4), "0 of 4 ayahs known")
        XCTAssertEqual(StartHerePath.progressText(known: 7, ayahCount: 7), "All 7 ayahs known")
        XCTAssertEqual(StartHerePath.progressText(known: 9, ayahCount: 7), "All 7 ayahs known")
    }

    func testRefsCoverTheWholeSurah() {
        XCTAssertEqual(StartHerePath.refs(sura: 112, ayahCount: 4), [
            AyahRef(sura: 112, aya: 1), AyahRef(sura: 112, aya: 2), AyahRef(sura: 112, aya: 3), AyahRef(sura: 112, aya: 4)
        ])
        XCTAssertEqual(StartHerePath.refs(sura: 1, ayahCount: 0), [])
    }
}
