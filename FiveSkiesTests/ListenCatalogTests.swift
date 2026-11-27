import XCTest
@testable import FiveSkies

/// A relay that answers from canned JSON by exact relative path. Unknown paths act as offline.
final class ListenFakeRelay: RelayFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Result<Data, Error>] = [:]
    private var log: [String] = []

    func serve(_ path: String, json: String) {
        lock.withLock { answers[path] = .success(Data(json.utf8)) }
    }

    func fail(_ path: String, with error: Error) {
        lock.withLock { answers[path] = .failure(error) }
    }

    var requested: [String] {
        lock.withLock { log }
    }

    func data(relativePath: String) async throws -> Data {
        let result: Result<Data, Error>? = lock.withLock {
            log.append(relativePath)
            return answers[relativePath]
        }
        guard let result else { throw RelayError.transport }
        return try result.get()
    }
}

/// A clock the test can move.
final class ListenTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) {
        current = date
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

final class ListenCatalogTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let recitersPath = "/api/v4/resources/chapter_reciters?language=en"

    // Shaped like the documented answer. Made-up names only.
    private static let recitersJSON = """
    {
      "reciters": [
        {
          "id": 7,
          "reciter_id": 70,
          "name": "Sample Reader Plain",
          "beta": false,
          "style": {"name": "Murattal", "language_name": "english"},
          "qirat": {"name": "Sample Qirat", "language_name": "english"},
          "translated_name": {"name": "Sample Reader Seven", "language_name": "english"},
          "some_future_field": {"nested": [1, 2, 3]}
        },
        {
          "id": 8,
          "name": "Sample Reader Eight",
          "style": {"name": null, "language_name": "english"},
          "translated_name": null
        },
        {
          "id": "9",
          "name": "Sample Reader Nine",
          "style": "Mujawwad",
          "translated_name": {"name": "Other Language Label", "language_name": "french"}
        },
        {
          "name": "No Id Reader",
          "translated_name": {"name": "No Id Reader", "language_name": "english"}
        },
        {
          "id": 10,
          "name": "   ",
          "translated_name": {"name": "", "language_name": "english"}
        },
        "not an object",
        {
          "id": 7,
          "name": "Duplicate Id Reader"
        }
      ]
    }
    """

    private var relay: ListenFakeRelay!
    private var clock: ListenTestClock!

    override func setUp() {
        super.setUp()
        relay = ListenFakeRelay()
        clock = ListenTestClock(Self.start)
    }

    override func tearDown() {
        relay = nil
        clock = nil
        super.tearDown()
    }

    private func makeCatalog() -> RelayListenCatalog {
        let clock = self.clock!
        return RelayListenCatalog(client: relay, now: { clock.now })
    }

    private func audioPath(_ reciter: Int, _ chapter: Int) -> String {
        "/api/v4/chapter_recitations/\(reciter)/\(chapter)"
    }

    /// Runs the body and returns the catalog error it threw, or nil when it did not throw one.
    private func catalogError(_ body: () async throws -> Void) async -> ListenCatalogError? {
        do {
            try await body()
            return nil
        } catch {
            return error as? ListenCatalogError
        }
    }

    /// A short run of letters from the Arabic script block, built from code points at run time.
    private static func arabicScriptSample() -> String {
        let values: [UInt32] = [0x0628, 0x0632, 0x0635]
        var scalars = String.UnicodeScalarView()
        for value in values {
            if let scalar = Unicode.Scalar(value) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    // MARK: - Reciters

    func testRecitersUseDocumentedPathAndEnglishNames() async throws {
        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let reciters = try await makeCatalog().reciters()

        XCTAssertEqual(relay.requested, [Self.recitersPath])
        XCTAssertEqual(reciters, [
            Reciter(id: 7, name: "Sample Reader Seven", style: "Murattal"),
            Reciter(id: 8, name: "Sample Reader Eight", style: nil),
            Reciter(id: 9, name: "Sample Reader Nine", style: "Mujawwad"),
        ])
    }

    func testNameInArabicScriptIsNeverUsed() async throws {
        let other = Self.arabicScriptSample()
        relay.serve(Self.recitersPath, json: """
        {"reciters": [
          {"id": 1, "name": "English Name One", "translated_name": {"name": "\(other)", "language_name": "english"}},
          {"id": 2, "name": "\(other)", "translated_name": {"name": "\(other)", "language_name": "arabic"}},
          {"id": 3, "name": "English Name Three", "style": {"name": "\(other)", "language_name": "arabic"}}
        ]}
        """)
        let reciters = try await makeCatalog().reciters()

        XCTAssertEqual(reciters, [
            Reciter(id: 1, name: "English Name One", style: nil),
            Reciter(id: 3, name: "English Name Three", style: nil),
        ])
        XCTAssertFalse(reciters.contains { ListenCatalogText.containsArabicScript($0.name) })
    }

    func testEmptyReciterListIsNotAvailableAndNotCached() async throws {
        relay.serve(Self.recitersPath, json: #"{"reciters": []}"#)
        let catalog = makeCatalog()
        let error = await catalogError { _ = try await catalog.reciters() }
        XCTAssertEqual(error, .notAvailable)
        XCTAssertEqual(error?.userMessage, "Recitations are not available right now.")

        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let reciters = try await catalog.reciters()
        XCTAssertEqual(reciters.count, 3)
        XCTAssertEqual(relay.requested.count, 2)
    }

    // MARK: - Cache

    func testReciterListIsCachedWithinTheHour() async throws {
        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let catalog = makeCatalog()

        let first = try await catalog.reciters()
        clock.now = Self.start.addingTimeInterval(59 * 60)
        let second = try await catalog.reciters()

        XCTAssertEqual(first, second)
        XCTAssertEqual(relay.requested.count, 1)
    }

    func testReciterListIsFetchedAgainAfterTheHour() async throws {
        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let catalog = makeCatalog()

        _ = try await catalog.reciters()
        clock.now = Self.start.addingTimeInterval(60 * 60 + 1)
        _ = try await catalog.reciters()

        XCTAssertEqual(relay.requested.count, 2)
    }

    func testClockGoingBackwardsRefetches() async throws {
        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let catalog = makeCatalog()

        _ = try await catalog.reciters()
        clock.now = Self.start.addingTimeInterval(-60)
        _ = try await catalog.reciters()

        XCTAssertEqual(relay.requested.count, 2)
    }

    func testFailureIsNotCached() async throws {
        relay.fail(Self.recitersPath, with: RelayError.transport)
        let catalog = makeCatalog()
        let error = await catalogError { _ = try await catalog.reciters() }
        XCTAssertEqual(error, .offline)

        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let reciters = try await catalog.reciters()
        XCTAssertEqual(reciters.count, 3)
        XCTAssertEqual(relay.requested.count, 2)
    }

    func testClearCacheRefetches() async throws {
        relay.serve(Self.recitersPath, json: Self.recitersJSON)
        let catalog = makeCatalog()
        _ = try await catalog.reciters()
        await catalog.clearCache()
        _ = try await catalog.reciters()
        XCTAssertEqual(relay.requested.count, 2)
    }

    // MARK: - Chapter audio

    func testChapterAudioWithFullURL() async throws {
        relay.serve(audioPath(7, 1), json: """
        {"audio_file": {
          "id": 457,
          "chapter_id": 1,
          "file_size": 710784,
          "format": "mp3",
          "audio_url": "https://download.quranicaudio.com/qdc/sample_reader/murattal/1.mp3",
          "duration": 53092,
          "timestamps": [{"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 6493, "duration": -6493}]
        }}
        """)
        let audio = try await makeCatalog().chapterAudio(reciterID: 7, chapter: 1)

        XCTAssertEqual(relay.requested, [audioPath(7, 1)])
        XCTAssertEqual(audio.reciterID, 7)
        XCTAssertEqual(audio.chapter, 1)
        XCTAssertEqual(audio.url.absoluteString, "https://download.quranicaudio.com/qdc/sample_reader/murattal/1.mp3")
        XCTAssertEqual(try XCTUnwrap(audio.durationSeconds), 53.092, accuracy: 0.0001)
    }

    func testChapterAudioWithRelativePath() async throws {
        relay.serve(audioPath(7, 2), json: """
        {"audio_file": {"chapter_id": 2, "audio_url": "qdc/sample_reader/murattal/2.mp3", "duration": null}}
        """)
        let audio = try await makeCatalog().chapterAudio(reciterID: 7, chapter: 2)

        XCTAssertEqual(audio.url.absoluteString, "https://download.quranicaudio.com/qdc/sample_reader/murattal/2.mp3")
        XCTAssertNil(audio.durationSeconds)
    }

    func testChapterAudioFromListShapePicksTheRightChapter() async throws {
        relay.serve(audioPath(7, 3), json: """
        {"audio_files": [
          {"chapter_id": 2, "audio_url": "https://audio.example.com/2.mp3"},
          {"chapter_id": "3", "audio_url": "https://audio.example.com/3.mp3", "duration": "1500"}
        ]}
        """)
        let audio = try await makeCatalog().chapterAudio(reciterID: 7, chapter: 3)

        XCTAssertEqual(audio.url.absoluteString, "https://audio.example.com/3.mp3")
        XCTAssertEqual(try XCTUnwrap(audio.durationSeconds), 1.5, accuracy: 0.0001)
    }

    func testChapterAudioForAnotherChapterIsRefused() async {
        relay.serve(audioPath(7, 4), json: #"{"audio_file": {"chapter_id": 5, "audio_url": "https://audio.example.com/5.mp3"}}"#)
        let catalog = makeCatalog()
        let error = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 4) }
        XCTAssertEqual(error, .notFound)
    }

    func testMissingAudioFileIsNotFound() async {
        relay.serve(audioPath(7, 5), json: #"{"something_else": true}"#)
        let catalog = makeCatalog()
        let error = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 5) }
        XCTAssertEqual(error, .notFound)
    }

    func testUnusableAudioURLIsUnexpected() async {
        relay.serve(audioPath(7, 6), json: #"{"audio_file": {"chapter_id": 6, "audio_url": "file:///private/sample.mp3"}}"#)
        let catalog = makeCatalog()
        let error = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 6) }
        XCTAssertEqual(error, .unexpected)
    }

    func testOutOfRangeChapterMakesNoRequest() async {
        let catalog = makeCatalog()
        let zero = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 0) }
        let high = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 115) }
        let badReciter = await catalogError { _ = try await catalog.chapterAudio(reciterID: 0, chapter: 1) }
        XCTAssertEqual(zero, .notFound)
        XCTAssertEqual(high, .notFound)
        XCTAssertEqual(badReciter, .notFound)
        XCTAssertTrue(relay.requested.isEmpty)
    }

    // MARK: - URL resolution

    func testAudioURLResolution() {
        func resolved(_ raw: String?) -> String? {
            ChapterAudioURL.resolve(raw)?.absoluteString
        }
        XCTAssertEqual(resolved("https://audio.example.com/a/1.mp3"), "https://audio.example.com/a/1.mp3")
        XCTAssertEqual(resolved("  https://audio.example.com/a/1.mp3\n"), "https://audio.example.com/a/1.mp3")
        XCTAssertEqual(resolved("http://audio.example.com/a/1.mp3"), "https://audio.example.com/a/1.mp3")
        XCTAssertEqual(resolved("//audio.example.com/a/1.mp3"), "https://audio.example.com/a/1.mp3")
        XCTAssertEqual(resolved("qdc/a/1.mp3"), "https://download.quranicaudio.com/qdc/a/1.mp3")
        XCTAssertEqual(resolved("/qdc/a/1.mp3"), "https://download.quranicaudio.com/qdc/a/1.mp3")

        XCTAssertNil(resolved(nil))
        XCTAssertNil(resolved(""))
        XCTAssertNil(resolved("   "))
        XCTAssertNil(resolved("file:///private/a.mp3"))
        XCTAssertNil(resolved("ftp://audio.example.com/a.mp3"))
        XCTAssertNil(resolved("javascript:alert(1)"))
        XCTAssertNil(resolved("../outside/a.mp3"))
        XCTAssertNil(resolved("https://"))
    }

    // MARK: - Errors

    func testRelayErrorsMapToPlainErrors() {
        XCTAssertEqual(ListenCatalogError.from(RelayError.notConfigured), .notAvailable)
        XCTAssertEqual(ListenCatalogError.from(RelayError.unauthorized), .notAvailable)
        XCTAssertEqual(ListenCatalogError.from(RelayError.rateLimited), .busy)
        XCTAssertEqual(ListenCatalogError.from(RelayError.server(status: 503)), .serviceTrouble)
        XCTAssertEqual(ListenCatalogError.from(RelayError.client(status: 404, code: "not_found")), .notFound)
        XCTAssertEqual(ListenCatalogError.from(RelayError.client(status: 422, code: nil)), .unexpected)
        XCTAssertEqual(ListenCatalogError.from(RelayError.transport), .offline)
        XCTAssertEqual(ListenCatalogError.from(RelayError.decoding), .unexpected)
        XCTAssertEqual(ListenCatalogError.from(RelayError.invalidPath), .unexpected)
        XCTAssertEqual(ListenCatalogError.from(URLError(.timedOut) as Error), .unexpected)
    }

    func testCatalogCallsSurfacePlainErrors() async {
        let cases: [(RelayError, ListenCatalogError)] = [
            (.transport, .offline),
            (.rateLimited, .busy),
            (.server(status: 502), .serviceTrouble),
            (.unauthorized, .notAvailable),
            (.client(status: 404, code: nil), .notFound),
        ]
        for (relayError, expected) in cases {
            let failing = ListenFakeRelay()
            failing.fail(Self.recitersPath, with: relayError)
            failing.fail(audioPath(7, 1), with: relayError)
            let catalog = RelayListenCatalog(client: failing)
            let listError = await catalogError { _ = try await catalog.reciters() }
            let audioError = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 1) }
            XCTAssertEqual(listError, expected, "reciters, \(relayError)")
            XCTAssertEqual(audioError, expected, "audio, \(relayError)")
        }
    }

    func testUnreadableAnswerIsUnexpected() async {
        relay.serve(Self.recitersPath, json: "[1, 2, 3]")
        relay.serve(audioPath(7, 1), json: "not json")
        let catalog = makeCatalog()
        let listError = await catalogError { _ = try await catalog.reciters() }
        let audioError = await catalogError { _ = try await catalog.chapterAudio(reciterID: 7, chapter: 1) }
        XCTAssertEqual(listError, .unexpected)
        XCTAssertEqual(audioError, .unexpected)
    }

    func testCancellationIsNotMapped() async {
        relay.fail(Self.recitersPath, with: CancellationError())
        let catalog = makeCatalog()
        do {
            _ = try await catalog.reciters()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testMessagesArePlain() {
        let all: [ListenCatalogError] = [.notAvailable, .offline, .busy, .serviceTrouble, .notFound, .unexpected]
        for error in all {
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.userMessage.contains("\u{2014}"))
            XCTAssertEqual(error.errorDescription, error.userMessage)
            XCTAssertEqual((error as Error).localizedDescription, error.userMessage)
        }
        XCTAssertEqual(ListenCatalogError.notAvailable.userMessage, "Recitations are not available right now.")
    }

    // MARK: - Fake and factory

    func testFakeCatalogServesThreeMadeUpReciters() async throws {
        let fake = FakeListenCatalog()
        let reciters = try await fake.reciters()
        XCTAssertEqual(reciters.map(\.name), ["Reciter One", "Reciter Two", "Reciter Three"])

        let audio = try await fake.chapterAudio(reciterID: 2, chapter: 18)
        XCTAssertEqual(audio.url.host, "example.com")
        XCTAssertEqual(audio.url.absoluteString, "https://example.com/listen/reciter-2/018.mp3")
        XCTAssertEqual(audio.reciterID, 2)
        XCTAssertEqual(audio.chapter, 18)

        let unknown = await catalogError { _ = try await fake.chapterAudio(reciterID: 99, chapter: 1) }
        XCTAssertEqual(unknown, .notFound)
    }

    func testFakeCatalogCanFail() async {
        let fake = FakeListenCatalog(failure: .offline)
        let error = await catalogError { _ = try await fake.reciters() }
        XCTAssertEqual(error, .offline)
    }

    func testLiveCatalogInUnitTestsIsNotAvailable() async {
        // The unit test host never has a relay config, and has no -FSFakeListen argument.
        let catalog = ListenCatalogFactory.live()
        XCTAssertTrue(catalog is UnavailableListenCatalog)
        let error = await catalogError { _ = try await catalog.reciters() }
        XCTAssertEqual(error, .notAvailable)
    }
}
