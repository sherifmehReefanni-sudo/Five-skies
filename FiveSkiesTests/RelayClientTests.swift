import XCTest
@testable import FiveSkies

/// Serves canned answers to a URLSession, and records the last request. No network.
final class RelayStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class RelayClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        RelayStubURLProtocol.handler = nil
        RelayStubURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RelayStubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        RelayStubURLProtocol.handler = nil
        RelayStubURLProtocol.requests = []
        session = nil
        super.tearDown()
    }

    private func makeClient(base: String = "https://relay.example.test", appKey: String? = "test-app-key") throws -> RelayClient {
        let config = try XCTUnwrap(RelayConfig.make(baseURLString: base, appKey: appKey))
        return RelayClient(config: config, session: session)
    }

    private func respond(status: Int, body: String = "{}") {
        RelayStubURLProtocol.handler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
            guard let response else { throw URLError(.badServerResponse) }
            return (response, Data(body.utf8))
        }
    }

    // MARK: - Config

    func testConfigNeedsABaseURL() {
        XCTAssertNil(RelayConfig.make(baseURLString: nil, appKey: "key"))
        XCTAssertNil(RelayConfig.make(baseURLString: "", appKey: "key"))
        XCTAssertNil(RelayConfig.make(baseURLString: "   ", appKey: "key"))
        XCTAssertNil(RelayConfig.make(baseURLString: "not a url", appKey: nil))
        XCTAssertNil(RelayConfig.make(baseURLString: "ftp://relay.example.test", appKey: nil))
    }

    func testConfigTrimsTrailingSlashAndEmptyKey() throws {
        let config = try XCTUnwrap(RelayConfig.make(baseURLString: "https://relay.example.test/", appKey: ""))
        XCTAssertEqual(config.baseURL.absoluteString, "https://relay.example.test")
        XCTAssertNil(config.appKey)
    }

    func testUnitTestHostIsNeverConnected() {
        XCTAssertFalse(RelayConfig.networkAllowed())
        XCTAssertNil(RelayConfig.fromBundle())
        XCTAssertFalse(TranslationStore.live().isConnected)
    }

    // MARK: - URL joining

    func testRelativeSyncPathsGetTheContentPrefix() throws {
        let base = try XCTUnwrap(URL(string: "https://relay.example.test"))
        let url = try RelayClient.url(base: base, relativePath: "/api/v4/resources/sync?cursor=abc%3D&per_page=100&resources=translations%3A20")
        XCTAssertEqual(url.absoluteString, "https://relay.example.test/content/api/v4/resources/sync?cursor=abc%3D&per_page=100&resources=translations%3A20")
    }

    func testSnapshotPathJoinsWithTrailingSlashBaseAndBasePath() throws {
        let slashed = try XCTUnwrap(URL(string: "https://relay.example.test/"))
        XCTAssertEqual(
            try RelayClient.url(base: slashed, relativePath: "/api/v4/resources/snapshots/translations/20").absoluteString,
            "https://relay.example.test/content/api/v4/resources/snapshots/translations/20"
        )
        let withPath = try XCTUnwrap(URL(string: "https://relay.example.test/relay"))
        XCTAssertEqual(
            try RelayClient.url(base: withPath, relativePath: "/api/v4/resources/translations").absoluteString,
            "https://relay.example.test/relay/content/api/v4/resources/translations"
        )
    }

    func testContentPrefixIsNotDoubled() throws {
        let base = try XCTUnwrap(URL(string: "https://relay.example.test"))
        XCTAssertEqual(
            try RelayClient.url(base: base, relativePath: "/content/api/v4/resources/translations").absoluteString,
            "https://relay.example.test/content/api/v4/resources/translations"
        )
    }

    func testAbsoluteAndUnsafePathsAreRejected() throws {
        let base = try XCTUnwrap(URL(string: "https://relay.example.test"))
        for path in ["https://other.example.test/api/v4/x", "api/v4/resources", "/api/v3/resources", "/api/v4/../secret", "/api/v4/a?next=https://other.example.test"] {
            XCTAssertThrowsError(try RelayClient.url(base: base, relativePath: path), path) { error in
                XCTAssertEqual(error as? RelayError, .invalidPath)
            }
        }
    }

    // MARK: - Requests

    func testGetSendsAppKeyAndDecodesSnakeCase() async throws {
        respond(status: 200, body: """
        {"translations":[{"id":1,"name":"Sample Name","author_name":"Sample Author","slug":"sample-slug","language_name":"english","translated_name":{"name":"Sample Name","language_name":"english"}}]}
        """)
        let client = try makeClient()
        let list = try await client.listTranslations()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.authorName, "Sample Author")
        XCTAssertEqual(list.first?.languageName, "english")
        XCTAssertEqual(list.first?.translatedName?.languageName, "english")

        let request = try XCTUnwrap(RelayStubURLProtocol.requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-key"), "test-app-key")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://relay.example.test/content/api/v4/resources/translations")
    }

    func testNoAppKeyHeaderWithoutAKey() async throws {
        respond(status: 200, body: "{}")
        let client = try makeClient(appKey: nil)
        _ = try await client.data(relativePath: "/api/v4/chapters")
        let request = try XCTUnwrap(RelayStubURLProtocol.requests.last)
        XCTAssertNil(request.value(forHTTPHeaderField: "x-app-key"))
    }

    func testHealth() async throws {
        respond(status: 200, body: #"{"ok":true,"environment":"prelive"}"#)
        let client = try makeClient()
        let health = try await client.health()
        XCTAssertEqual(health, RelayHealth(ok: true, environment: "prelive"))
        XCTAssertEqual(RelayStubURLProtocol.requests.last?.url?.absoluteString, "https://relay.example.test/health")
    }

    // MARK: - Error mapping

    private func mappedError(status: Int, body: String = "{}") async throws -> RelayError? {
        respond(status: status, body: body)
        let client = try makeClient()
        do {
            _ = try await client.data(relativePath: "/api/v4/resources/translations")
            return nil
        } catch {
            return error as? RelayError
        }
    }

    func testStatusCodesMapToTypedErrors() async throws {
        let unauthorized = try await mappedError(status: 401, body: #"{"error":"unauthorized"}"#)
        XCTAssertEqual(unauthorized, .unauthorized)
        let forbidden = try await mappedError(status: 403)
        XCTAssertEqual(forbidden, .unauthorized)
        let limited = try await mappedError(status: 429, body: #"{"error":"rate_limited"}"#)
        XCTAssertEqual(limited, .rateLimited)
        let server = try await mappedError(status: 503)
        XCTAssertEqual(server, .server(status: 503))
        let gateway = try await mappedError(status: 502, body: #"{"error":"upstream_unreachable"}"#)
        XCTAssertEqual(gateway, .server(status: 502))
    }

    func testSyncErrorCodeIsKept() async throws {
        let gone = try await mappedError(status: 410, body: #"{"error":{"code":"resync_required","message":"sample message"}}"#)
        XCTAssertEqual(gone, .client(status: 410, code: "resync_required"))
        let missing = try await mappedError(status: 404, body: #"{"error":{"code":"snapshot_not_found","message":"sample message"}}"#)
        XCTAssertEqual(missing, .client(status: 404, code: "snapshot_not_found"))
        let generic = try await mappedError(status: 400, body: #"{"message":"sample message","type":"invalid_request","success":false}"#)
        XCTAssertEqual(generic, .client(status: 400, code: "invalid_request"))
        let empty = try await mappedError(status: 404, body: "not json")
        XCTAssertEqual(empty, .client(status: 404, code: nil))
    }

    func testTransportFailureMapsToTransport() async throws {
        RelayStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = try makeClient()
        do {
            _ = try await client.data(relativePath: "/api/v4/resources/translations")
            XCTFail("Expected a transport error")
        } catch {
            XCTAssertEqual(error as? RelayError, .transport)
        }
    }

    func testBadJSONMapsToDecoding() async throws {
        respond(status: 200, body: "[1, 2")
        let client = try makeClient()
        do {
            _ = try await client.listTranslations()
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertEqual(error as? RelayError, .decoding)
        }
    }

    func testTokenRejectionDetection() {
        XCTAssertTrue(ContentSyncErrorCode.isTokenRejection(RelayError.client(status: 410, code: "resync_required")))
        XCTAssertTrue(ContentSyncErrorCode.isTokenRejection(RelayError.client(status: 422, code: "token_filter_mismatch")))
        XCTAssertTrue(ContentSyncErrorCode.isTokenRejection(RelayError.client(status: 410, code: nil)))
        XCTAssertFalse(ContentSyncErrorCode.isTokenRejection(RelayError.transport))
        XCTAssertFalse(ContentSyncErrorCode.isTokenRejection(RelayError.client(status: 422, code: "invalid_per_page")))
    }
}
