import XCTest
@testable import FiveSkies

final class QuranStoresTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "QuranStoresTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Bookmarks

    func testBookmarksStartEmpty() {
        let store = QuranBookmarksStore(defaults: defaults)
        XCTAssertEqual(store.bookmarks, [])
        XCTAssertFalse(store.contains(AyahRef(sura: 1, aya: 1)))
    }

    func testAddingAndRemovingBookmarks() {
        let store = QuranBookmarksStore(defaults: defaults)
        store.add(AyahRef(sura: 18, aya: 10))
        store.add(AyahRef(sura: 2, aya: 255))
        store.add(AyahRef(sura: 2, aya: 255))
        XCTAssertEqual(store.bookmarks, [AyahRef(sura: 2, aya: 255), AyahRef(sura: 18, aya: 10)])
        XCTAssertTrue(store.contains(AyahRef(sura: 18, aya: 10)))

        store.remove(AyahRef(sura: 2, aya: 255))
        XCTAssertEqual(store.bookmarks, [AyahRef(sura: 18, aya: 10)])

        store.toggle(AyahRef(sura: 18, aya: 10))
        XCTAssertEqual(store.bookmarks, [])
        store.toggle(AyahRef(sura: 36, aya: 1))
        XCTAssertEqual(store.bookmarks, [AyahRef(sura: 36, aya: 1)])
    }

    func testBookmarksPersistAcrossInstances() {
        let writer = QuranBookmarksStore(defaults: defaults)
        writer.add(AyahRef(sura: 112, aya: 1))
        writer.add(AyahRef(sura: 1, aya: 7))

        let reader = QuranBookmarksStore(defaults: defaults)
        XCTAssertEqual(reader.bookmarks, [AyahRef(sura: 1, aya: 7), AyahRef(sura: 112, aya: 1)])

        reader.remove(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(reader.bookmarks, [AyahRef(sura: 112, aya: 1)])
        XCTAssertEqual(QuranBookmarksStore(defaults: defaults).bookmarks, [AyahRef(sura: 112, aya: 1)])
    }

    func testBookmarksAreStoredAsNumbersOnly() throws {
        let store = QuranBookmarksStore(defaults: defaults)
        store.add(AyahRef(sura: 3, aya: 4))
        let data = try XCTUnwrap(defaults.data(forKey: QuranBookmarksStore.storageKey))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Int]]
        XCTAssertEqual(decoded, [["sura": 3, "aya": 4]])
    }

    // MARK: - Last read

    func testLastReadStartsEmpty() {
        XCTAssertNil(QuranLastReadStore(defaults: defaults).position)
    }

    func testLastReadPersistsAcrossInstances() {
        let writer = QuranLastReadStore(defaults: defaults)
        writer.update(AyahRef(sura: 18, aya: 45))
        XCTAssertEqual(writer.position, AyahRef(sura: 18, aya: 45))

        let reader = QuranLastReadStore(defaults: defaults)
        XCTAssertEqual(reader.position, AyahRef(sura: 18, aya: 45))

        reader.update(AyahRef(sura: 19, aya: 2))
        XCTAssertEqual(QuranLastReadStore(defaults: defaults).position, AyahRef(sura: 19, aya: 2))

        reader.clear()
        XCTAssertNil(QuranLastReadStore(defaults: defaults).position)
    }

    // MARK: - Loading

    @MainActor
    func testStoreReportsALoadFailure() async throws {
        let store = QuranStore(loader: { throw QuranParserError.unreadableFile("missing.txt") })
        for _ in 0..<200 {
            if case .failed = store.state { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard case .failed(let message) = store.state else {
            return XCTFail("The store did not report the failure")
        }
        XCTAssertTrue(message.contains("missing.txt"))
        XCTAssertNil(store.data)
    }

    @MainActor
    func testStoreLoadsTheBundledQuran() async throws {
        let store = QuranStore()
        for _ in 0..<500 {
            if store.data != nil { break }
            if case .failed = store.state { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let data = try XCTUnwrap(store.data, "The bundled Quran did not load")
        XCTAssertEqual(data.suras.count, 114)
        XCTAssertEqual(store.ayahs(inSura: 2).count, 286)
        XCTAssertEqual(store.page(for: AyahRef(sura: 1, aya: 1)), 1)
        XCTAssertEqual(store.juz(for: AyahRef(sura: 114, aya: 6)), 30)
        XCTAssertEqual(store.juzStarts.count, 30)
    }
}
