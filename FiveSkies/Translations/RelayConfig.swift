import Foundation

/// Where the Five Skies relay lives and the key the app sends to it.
/// Both come from the app's Info.plist (`FSRelayBaseURL`, `FSRelayAppKey`).
/// When the base URL is missing or empty the translation feature is "not connected"
/// and makes no network calls at all.
struct RelayConfig: Equatable, Sendable {
    static let baseURLInfoKey = "FSRelayBaseURL"
    static let appKeyInfoKey = "FSRelayAppKey"

    /// The relay origin, with no trailing slash, for example https://relay.example.com
    let baseURL: URL
    /// Sent as `x-app-key` when present.
    let appKey: String?

    /// Builds a config from raw strings. Returns nil when the base URL is missing, empty,
    /// not http(s) or has no host.
    static func make(baseURLString: String?, appKey: String?) -> RelayConfig? {
        guard var raw = baseURLString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else {
            return nil
        }
        let key = appKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RelayConfig(baseURL: url, appKey: (key?.isEmpty ?? true) ? nil : key)
    }

    /// Reads the Info.plist keys. Returns nil (not connected) for the fixed phase screenshot
    /// mode and inside the unit test host, so tests never touch the network.
    static func fromBundle(_ bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> RelayConfig? {
        guard networkAllowed(processInfo: processInfo) else { return nil }
        return make(
            baseURLString: bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String,
            appKey: bundle.object(forInfoDictionaryKey: appKeyInfoKey) as? String
        )
    }

    /// False with `-FSFixedPhase` among the launch arguments or when hosted by XCTest.
    static func networkAllowed(processInfo: ProcessInfo = .processInfo) -> Bool {
        if processInfo.arguments.contains(LaunchOptions.fixedPhaseArgument) {
            return false
        }
        if processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        return true
    }
}
