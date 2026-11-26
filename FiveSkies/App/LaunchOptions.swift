import Foundation

/// Reads the testing hooks from the launch arguments.
/// `-FSFixedPhase <fajr|dhuhr|asr|maghrib|isha>` freezes time inside that sky and skips location.
struct LaunchOptions {
    static let fixedPhaseArgument = "-FSFixedPhase"

    let fixedPhase: Prayer?
    let isUnitTestHost: Bool

    init(processInfo: ProcessInfo = .processInfo) {
        let arguments = processInfo.arguments
        if let index = arguments.firstIndex(of: Self.fixedPhaseArgument),
           arguments.indices.contains(index + 1) {
            fixedPhase = Prayer(rawValue: arguments[index + 1])
        } else {
            fixedPhase = nil
        }
        isUnitTestHost = processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Whether the app should ask for the device location.
    var requestsLocation: Bool {
        fixedPhase == nil && !isUnitTestHost
    }
}
