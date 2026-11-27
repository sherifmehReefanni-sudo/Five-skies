import Foundation

/// Typed failures from the relay. Response bodies are never logged or kept, only
/// the status and, for 4xx answers, the machine readable error code.
enum RelayError: Error, Equatable, Sendable {
    /// No relay base URL is configured.
    case notConfigured
    /// A path that is not a relative `/api/v4/...` path.
    case invalidPath
    /// 401 or 403.
    case unauthorized
    /// 429.
    case rateLimited
    /// 5xx.
    case server(status: Int)
    /// Any other non-2xx status, with the error code from the body when there is one
    /// (for example `resync_required` or `snapshot_not_found`).
    case client(status: Int, code: String?)
    /// No connection, timeout, TLS failure and the like.
    case transport
    /// The answer was not the JSON shape we expected.
    case decoding

    /// A short message for the person, never containing the response body.
    var userMessage: String {
        switch self {
        case .notConfigured:
            return "Translations will be available soon."
        case .invalidPath, .decoding, .client:
            return "Something went wrong. Try again."
        case .unauthorized:
            return "The translation service refused the request."
        case .rateLimited:
            return "Too many requests. Try again in a minute."
        case .server:
            return "The translation service is having trouble. Try again later."
        case .transport:
            return "No connection. Try again when you are online."
        }
    }
}

/// The calls the translation feature makes. A protocol so tests can serve canned answers.
protocol RelayFetching: Sendable {
    /// GETs a relative API path such as `/api/v4/resources/sync?...` and returns the body.
    func data(relativePath: String) async throws -> Data
}

extension RelayFetching {
    /// GETs a relative API path and decodes it with snake case conversion.
    func get<T: Decodable>(relativePath: String, as type: T.Type = T.self) async throws -> T {
        let body = try await data(relativePath: relativePath)
        do {
            return try RelayClient.makeDecoder().decode(T.self, from: body)
        } catch {
            throw RelayError.decoding
        }
    }

    /// `GET /resources/translations`: every translation the API offers.
    func listTranslations() async throws -> [TranslationInfo] {
        let list: TranslationListResponse = try await get(relativePath: "/api/v4/resources/translations")
        return list.translations
    }
}

/// One entry of `GET /resources/translations`.
struct TranslationInfo: Codable, Hashable, Identifiable, Sendable {
    struct TranslatedName: Codable, Hashable, Sendable {
        let name: String?
        let languageName: String?
    }

    let id: Int
    let name: String
    let authorName: String?
    let slug: String?
    let languageName: String?
    let translatedName: TranslatedName?

    init(id: Int, name: String, authorName: String?, slug: String? = nil, languageName: String?, translatedName: TranslatedName? = nil) {
        self.id = id
        self.name = name
        self.authorName = authorName
        self.slug = slug
        self.languageName = languageName
        self.translatedName = translatedName
    }
}

struct TranslationListResponse: Decodable, Sendable {
    let translations: [TranslationInfo]
}

/// Answer of the relay's own `GET /health`.
struct RelayHealth: Decodable, Equatable, Sendable {
    let ok: Bool
    let environment: String?
}

/// A small async client for the Five Skies relay.
struct RelayClient: RelayFetching {
    static let appKeyHeader = "x-app-key"
    static let contentPrefix = "/content"

    let config: RelayConfig
    let session: URLSession

    init(config: RelayConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Joins the relay base, `/content` and a relative API path.
    /// Accepts `/api/v4/...` (as Content Sync returns it) and `/content/api/v4/...`.
    /// The path and query are kept exactly as given, so cursors are never re-encoded.
    static func url(base: URL, relativePath: String) throws -> URL {
        let path: String
        if relativePath.hasPrefix("/api/v4/") {
            path = contentPrefix + relativePath
        } else if relativePath.hasPrefix("/content/api/v4/") {
            path = relativePath
        } else {
            throw RelayError.invalidPath
        }
        if path.contains("://") || path.contains("..") || path.contains("\\") {
            throw RelayError.invalidPath
        }
        var baseString = base.absoluteString
        while baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        guard let url = URL(string: baseString + path) else {
            throw RelayError.invalidPath
        }
        return url
    }

    /// Maps a status code and body to a typed error, or nil for 2xx.
    static func error(status: Int, body: Data) -> RelayError? {
        switch status {
        case 200...299:
            return nil
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited
        case 500...599:
            return .server(status: status)
        default:
            return .client(status: status, code: errorCode(in: body))
        }
    }

    /// Reads `error.code` (Content Sync errors) or `type` (generic errors) from an error body.
    static func errorCode(in body: Data) -> String? {
        struct Body: Decodable {
            struct Inner: Decodable { let code: String? }
            let error: Inner?
            let type: String?
        }
        guard let parsed = try? makeDecoder().decode(Body.self, from: body) else { return nil }
        return parsed.error?.code ?? parsed.type
    }

    func health() async throws -> RelayHealth {
        var raw = config.baseURL.absoluteString
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        guard let url = URL(string: raw + "/health") else { throw RelayError.invalidPath }
        let body = try await send(url)
        do {
            return try Self.makeDecoder().decode(RelayHealth.self, from: body)
        } catch {
            throw RelayError.decoding
        }
    }

    func data(relativePath: String) async throws -> Data {
        let url = try Self.url(base: config.baseURL, relativePath: relativePath)
        return try await send(url)
    }

    private func send(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let key = config.appKey {
            request.setValue(key, forHTTPHeaderField: Self.appKeyHeader)
        }
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw RelayError.transport
        }
        let body = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw RelayError.transport
        }
        if let error = Self.error(status: http.statusCode, body: body) {
            throw error
        }
        return body
    }
}
