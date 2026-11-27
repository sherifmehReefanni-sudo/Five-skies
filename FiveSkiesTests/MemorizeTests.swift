import XCTest
@testable import FiveSkies

final class MemorizeTests: XCTestCase {
    // MARK: - First words

    func testFirstTwoWordsOfALongerLine() {
        let split = MemorizeText.firstWords("alpha beta gamma delta", count: 2)
        XCTAssertEqual(split.prefix, "alpha beta")
        XCTAssertTrue(split.hasRemainder)
    }

    func testExactlyTwoWordsHasNoRemainder() {
        let split = MemorizeText.firstWords("alpha beta", count: 2)
        XCTAssertEqual(split.prefix, "alpha beta")
        XCTAssertFalse(split.hasRemainder)
    }

    func testOneWordIsShownWhole() {
        let split = MemorizeText.firstWords("alpha", count: 2)
        XCTAssertEqual(split.prefix, "alpha")
        XCTAssertFalse(split.hasRemainder)
    }

    func testEmptyText() {
        let split = MemorizeText.firstWords("", count: 2)
        XCTAssertEqual(split.prefix, "")
        XCTAssertFalse(split.hasRemainder)
    }

    func testTrailingSpaceIsNotARemainder() {
        let split = MemorizeText.firstWords("alpha beta ", count: 2)
        XCTAssertEqual(split.prefix, "alpha beta")
        XCTAssertFalse(split.hasRemainder)
    }

    func testRepeatedSpacesAreKeptInThePrefix() {
        let split = MemorizeText.firstWords("alpha  beta gamma", count: 2)
        XCTAssertEqual(split.prefix, "alpha  beta")
        XCTAssertTrue(split.hasRemainder)
    }

    func testPrefixIsTheStartOfTheStoredString() {
        let text = "one two three four five"
        let split = MemorizeText.firstWords(text, count: 2)
        XCTAssertTrue(text.hasPrefix(split.prefix))
        XCTAssertEqual(MemorizeText.firstWords(text, count: 3).prefix, "one two three")
    }

    func testOnlyTheASCIISpaceSeparatesWords() {
        // A tab is not a separator, so "a\tb" counts as one word.
        let split = MemorizeText.firstWords("a\tb c d", count: 2)
        XCTAssertEqual(split.prefix, "a\tb c")
        XCTAssertTrue(split.hasRemainder)
    }

    func testCombiningMarksStayIntact() {
        // "e" followed by a combining acute accent, built from scalars.
        let word = "e\u{0301}x"
        let text = "\(word) \(word) \(word)"
        let split = MemorizeText.firstWords(text, count: 2)
        XCTAssertEqual(split.prefix, "\(word) \(word)")
        XCTAssertEqual(split.prefix.unicodeScalars.count, 7)
        XCTAssertTrue(split.hasRemainder)
    }

    // MARK: - Progress store

    private func makeDefaults(file: StaticString = #filePath, line: UInt = #line) throws -> (UserDefaults, String) {
        let suite = "MemorizeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite), file: file, line: line)
        return (defaults, suite)
    }

    func testProgressRoundTrip() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MemorizeProgressStore(defaults: defaults)
        XCTAssertNil(store.status(for: AyahRef(sura: 2, aya: 255)))
        store.mark(AyahRef(sura: 2, aya: 255), as: .known)
        store.mark(AyahRef(sura: 1, aya: 1), as: .learning)
        store.mark(AyahRef(sura: 1, aya: 2), as: .known)

        let reloaded = MemorizeProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.status(for: AyahRef(sura: 2, aya: 255)), .known)
        XCTAssertEqual(reloaded.status(for: AyahRef(sura: 1, aya: 1)), .learning)
        XCTAssertEqual(reloaded.status(for: AyahRef(sura: 1, aya: 2)), .known)
        XCTAssertNil(reloaded.status(for: AyahRef(sura: 1, aya: 3)))
    }

    func testMarkingAgainReplacesAndClearRemoves() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MemorizeProgressStore(defaults: defaults)
        let ref = AyahRef(sura: 112, aya: 1)
        store.mark(ref, as: .learning)
        store.mark(ref, as: .known)
        XCTAssertEqual(MemorizeProgressStore(defaults: defaults).status(for: ref), .known)
        store.clear(ref)
        XCTAssertNil(MemorizeProgressStore(defaults: defaults).status(for: ref))
    }

    func testKnownCountOnlyCountsKnownInRange() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MemorizeProgressStore(defaults: defaults)
        store.mark(AyahRef(sura: 1, aya: 1), as: .known)
        store.mark(AyahRef(sura: 1, aya: 2), as: .learning)
        store.mark(AyahRef(sura: 1, aya: 3), as: .known)
        store.mark(AyahRef(sura: 2, aya: 1), as: .known)
        let refs = MemorizeText.refs(sura: 1, range: 1...7)
        XCTAssertEqual(refs.count, 7)
        XCTAssertEqual(store.knownCount(in: refs), 2)
    }

    func testStoredJSONHoldsOnlyNumbersAndStatus() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MemorizeProgressStore(defaults: defaults)
        store.mark(AyahRef(sura: 3, aya: 4), as: .known)
        let data = try XCTUnwrap(defaults.data(forKey: MemorizeProgressStore.storageKey))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.count, 1)
        let first = try XCTUnwrap(json.first)
        XCTAssertEqual(first["sura"] as? Int, 3)
        XCTAssertEqual(first["aya"] as? Int, 4)
        XCTAssertEqual(first["status"] as? String, "known")
        XCTAssertEqual(Set(first.keys), ["sura", "aya", "status"])
    }

    func testCorruptDataLoadsEmpty() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: MemorizeProgressStore.storageKey)
        XCTAssertTrue(MemorizeProgressStore(defaults: defaults).statuses.isEmpty)
    }

    func testModeTitles() {
        XCTAssertEqual(MemorizeMode.allCases.map(\.title), ["Read", "Hide", "First words"])
    }
}
