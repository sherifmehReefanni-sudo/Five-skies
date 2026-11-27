import Foundation

/// Plain failures of the reciter list and surah audio lookups.
/// The message is safe to show as is: it never contains a response body.
enum ListenCatalogError: Error, Equatable, Sendable, LocalizedError {
    /// No relay is set up, the service refused us, or it listed no reciters.
    case notAvailable
    /// No connection, timeout and the like.
    case offline
    /// Too many requests (429).
    case busy
    /// The service answered with a 5xx.
    case serviceTrouble
    /// This reciter has no file for this surah, or the surah number is out of range.
    case notFound
    /// Any other failure, including an answer we could not read.
    case unexpected

    var userMessage: String {
        switch self {
        case .notAvailable:
            return "Recitations are not available right now."
        case .offline:
            return "No connection. Try again when you are online."
        case .busy:
            return "Too many requests. Try again in a minute."
        case .serviceTrouble:
            return "The recitation service is having trouble. Try again later."
        case .notFound:
            return "This recitation is not available. Try another reciter."
        case .unexpected:
            return "Something went wrong. Try again."
        }
    }

    var errorDescription: String? { userMessage }

    /// Maps a relay failure to a plain one.
    static func from(_ error: RelayError) -> ListenCatalogError {
        switch error {
        case .notConfigured, .unauthorized:
            return .notAvailable
        case .rateLimited:
            return .busy
        case .server:
            return .serviceTrouble
        case .client(let status, _):
            return status == 404 ? .notFound : .unexpected
        case .transport:
            return .offline
        case .invalidPath, .decoding:
            return .unexpected
        }
    }

    /// Maps any error. Cancellation is not mapped here: callers rethrow it first.
    static func from(_ error: Error) -> ListenCatalogError {
        if let own = error as? ListenCatalogError { return own }
        if let relay = error as? RelayError { return from(relay) }
        return .unexpected
    }
}
