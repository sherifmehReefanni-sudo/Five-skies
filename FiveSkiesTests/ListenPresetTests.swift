import XCTest
@testable import FiveSkies

// Round E2.1 play presets: pure logic on PlayModes. No religious text.

final class ListenPresetTests: XCTestCase {
    func testEachPresetRoundTrips() {
        for preset in ListenPreset.allCases {
            let modes = preset.applied(to: PlayModes())
            XCTAssertEqual(ListenPreset.matching(modes), preset, "\(preset)")
        }
    }

    func testPresetsRoundTripFromEachOther() {
        for from in ListenPreset.allCases {
            for to in ListenPreset.allCases {
                let modes = to.applied(to: from.applied(to: PlayModes()))
                XCTAssertEqual(ListenPreset.matching(modes), to)
            }
        }
    }

    func testAppliedSetsTheFourFields() {
        let listen = ListenPreset.listen.applied(to: PlayModes())
        XCTAssertEqual(listen.ayahRepeat, 1)
        XCTAssertFalse(listen.reciteAfterMe)
        XCTAssertFalse(listen.readsMeaning)
        XCTAssertFalse(listen.hidesAyahWhileWaiting)

        let understand = ListenPreset.understand.applied(to: PlayModes())
        XCTAssertEqual(understand.ayahRepeat, 1)
        XCTAssertFalse(understand.reciteAfterMe)
        XCTAssertTrue(understand.readsMeaning)
        XCTAssertFalse(understand.hidesAyahWhileWaiting)

        let memorize = ListenPreset.memorize.applied(to: PlayModes())
        XCTAssertEqual(memorize.ayahRepeat, 3)
        XCTAssertTrue(memorize.reciteAfterMe)
        XCTAssertFalse(memorize.readsMeaning)
        XCTAssertTrue(memorize.hidesAyahWhileWaiting)
    }

    func testDefaultModesAreListen() {
        XCTAssertEqual(ListenPreset.matching(PlayModes()), .listen)
    }

    func testCustomMixMatchesNothing() {
        var modes = PlayModes()
        modes.ayahRepeat = 5
        XCTAssertNil(ListenPreset.matching(modes))

        var recite = PlayModes()
        recite.reciteAfterMe = true
        XCTAssertNil(ListenPreset.matching(recite))

        var both = ListenPreset.memorize.applied(to: PlayModes())
        both.readsMeaning = true
        XCTAssertNil(ListenPreset.matching(both))

        var noHide = ListenPreset.memorize.applied(to: PlayModes())
        noHide.hidesAyahWhileWaiting = false
        XCTAssertNil(ListenPreset.matching(noHide))
    }

    func testSurahEndAndPrayerPauseAreKept() {
        var modes = PlayModes()
        modes.surahEnd = .playSet(first: 2, last: 5)
        modes.pausesForPrayer = false
        for preset in ListenPreset.allCases {
            let result = preset.applied(to: modes)
            XCTAssertEqual(result.surahEnd, .playSet(first: 2, last: 5))
            XCTAssertFalse(result.pausesForPrayer)
        }

        var repeating = PlayModes()
        repeating.surahEnd = .repeatSurah(times: nil)
        XCTAssertEqual(ListenPreset.memorize.applied(to: repeating).surahEnd, .repeatSurah(times: nil))
        XCTAssertTrue(ListenPreset.memorize.applied(to: repeating).pausesForPrayer)
    }

    func testMatchingIgnoresSurahEndAndPrayerPause() {
        var modes = ListenPreset.understand.applied(to: PlayModes())
        modes.surahEnd = .playNext
        modes.pausesForPrayer = false
        XCTAssertEqual(ListenPreset.matching(modes), .understand)
    }

    func testRequirements() {
        XCTAssertFalse(ListenPreset.listen.needsTimings)
        XCTAssertTrue(ListenPreset.understand.needsTimings)
        XCTAssertTrue(ListenPreset.memorize.needsTimings)
        XCTAssertEqual(ListenPreset.allCases.filter(\.needsTranslation), [.understand])
        XCTAssertEqual(ListenPreset.allCases.filter(\.showsReadingAids), [.understand])
    }

    func testIdentifiersAndTitles() {
        XCTAssertEqual(ListenPreset.allCases.map(\.identifier), ["presetListen", "presetUnderstand", "presetMemorize"])
        XCTAssertEqual(ListenPreset.allCases.map(\.title), ["Listen", "Understand", "Memorize"])
        for preset in ListenPreset.allCases {
            XCTAssertFalse(preset.subtitle.isEmpty)
            XCTAssertFalse(preset.symbol.isEmpty)
        }
    }

    func testOldSavedModesDecodeWithoutHiding() throws {
        let json = #"{"ayahRepeat":3,"reciteAfterMe":true,"pausesForPrayer":false,"readsMeaning":false}"#
        let modes = try JSONDecoder().decode(PlayModes.self, from: Data(json.utf8))
        XCTAssertFalse(modes.hidesAyahWhileWaiting)
        XCTAssertEqual(modes.ayahRepeat, 3)
        XCTAssertTrue(modes.reciteAfterMe)
        XCTAssertFalse(modes.pausesForPrayer)
        XCTAssertEqual(modes.surahEnd, .stop)
        // Without the hide flag this older copy is not Memorize; it shows as Custom.
        XCTAssertNil(ListenPreset.matching(modes))
    }

    func testEncodeDecodeKeepsHiding() throws {
        let modes = ListenPreset.memorize.applied(to: PlayModes())
        let decoded = try JSONDecoder().decode(PlayModes.self, from: JSONEncoder().encode(modes))
        XCTAssertEqual(decoded, modes)
        XCTAssertEqual(ListenPreset.matching(decoded), .memorize)
    }
}
