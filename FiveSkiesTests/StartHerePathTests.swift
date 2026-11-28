import XCTest
@testable import FiveSkies

final class StartHerePathTests: XCTestCase {
    private static let path = [1, 112, 113, 114, 108, 103]

    func testPathIsComputedFromTheBundledText() throws {
        // FABLE decision 2: the order is worked out from ayah and word counts, not typed.
        let data = try QuranBundle.load()
        let path = StartHerePath.surahs(in: data)
        XCTAssertEqual(Array(path.prefix(4)), StartHerePath.opening)
        XCTAssertEqual(Set(path.dropFirst(4)), Set(StartHerePath.shortSurahs))
        XCTAssertEqual(Set(path).count, path.count, "A surah appears twice")
        // Shortest first by ayah count, then words.
        let rest = Array(path.dropFirst(4))
        for (earlier, later) in zip(rest, rest.dropFirst()) {
            let a = data.ayahs(inSura: earlier).count
            let b = data.ayahs(inSura: later).count
            XCTAssertLessThanOrEqual(a, b)
        }
        // The result Fable expected, checked here rather than written into the app.
        XCTAssertEqual(rest, [108, 103, 110, 106, 111, 105, 109, 107, 104])
    }

    func testTiesBreakByWordsThenLaterSurah() throws {
        let data = try QuranBundle.load()
        // 105 and 111 both have 5 ayahs and the same number of words: the later surah comes first.
        XCTAssertEqual(StartHerePath.order([105, 111], in: data), [111, 105])
        XCTAssertEqual(StartHerePath.order([110, 103, 108], in: data), [108, 103, 110])
    }

    func testNextStepIsTheFirstNotFullyKnown() {
        let path = Self.path
        XCTAssertEqual(StartHerePath.nextStep(known: [], path: path), 1)
        XCTAssertEqual(StartHerePath.nextStep(known: [1], path: path), 112)
        XCTAssertEqual(StartHerePath.nextStep(known: [1, 112, 113], path: path), 114)
        // Knowing a later surah first does not skip an earlier step.
        XCTAssertEqual(StartHerePath.nextStep(known: [112, 113], path: path), 1)
        XCTAssertEqual(StartHerePath.nextStep(known: [1, 113], path: path), 112)
        // Surahs that are not on the path change nothing.
        XCTAssertEqual(StartHerePath.nextStep(known: [2, 36], path: path), 1)
    }

    func testNextStepIsNilWhenAllKnown() {
        XCTAssertNil(StartHerePath.nextStep(known: Set(Self.path), path: Self.path))
        XCTAssertNil(StartHerePath.nextStep(known: Set(Self.path).union([2]), path: Self.path))
    }

    func testTeacherNoteIsPlain() {
        XCTAssertFalse(StartHerePath.teacherNote.contains("\u{2014}"))
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
