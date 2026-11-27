import Foundation

/// The app's sky theme. Living sky follows the prayer times; the others are fixed skies.
/// Stored as its raw value under `storageKey`.
enum SkyTheme: String, CaseIterable, Identifiable, Codable {
    case living
    case midnight
    case emerald
    case desert

    static let storageKey = "appearance.skyTheme"
    static let defaultTheme = SkyTheme.living
    /// `-FSTheme <living|midnight|emerald|desert>` picks the theme for screenshots.
    static let launchArgument = "-FSTheme"

    /// Read once: the launch arguments never change while the app runs.
    static let processArguments = ProcessInfo.processInfo.arguments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .living: return "Living sky"
        case .midnight: return "Midnight"
        case .emerald: return "Emerald"
        case .desert: return "Desert dawn"
        }
    }

    var caption: String {
        switch self {
        case .living: return "Follows the prayer times"
        case .midnight: return "Deep night blues"
        case .emerald: return "Green and teal"
        case .desert: return "Plum to warm sand"
        }
    }

    /// The fixed sky gradient as (0xRRGGBB, location) pairs, or nil for the living sky.
    var gradient: [(hex: UInt32, location: Double)]? {
        switch self {
        case .living: return nil
        case .midnight: return [(0x03061A, 0), (0x141E55, 0.55), (0x2E2560, 1)]
        case .emerald: return [(0x04201C, 0), (0x0C5A58, 0.55), (0x16907A, 1)]
        case .desert: return [(0x2A1638, 0), (0x8E5A86, 0.45), (0xF0A070, 1)]
        }
    }

    /// The theme named after `-FSTheme`, if it is there and valid.
    static func launchTheme(in arguments: [String]) -> SkyTheme? {
        guard let index = arguments.firstIndex(of: launchArgument), arguments.indices.contains(index + 1) else {
            return nil
        }
        return SkyTheme(rawValue: arguments[index + 1].lowercased())
    }

    /// The theme to draw: `-FSTheme` wins; the fixed phase screenshot mode is otherwise always
    /// the living sky; otherwise the stored choice.
    static func effective(stored: SkyTheme, arguments: [String]) -> SkyTheme {
        if let forced = launchTheme(in: arguments) {
            return forced
        }
        if arguments.contains(LaunchOptions.fixedPhaseArgument) {
            return .living
        }
        return stored
    }
}

/// Reads and writes the stored theme. Uses the same key and format as `@AppStorage(SkyTheme.storageKey)`.
struct ThemeStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var theme: SkyTheme {
        defaults.string(forKey: SkyTheme.storageKey).flatMap(SkyTheme.init(rawValue:)) ?? SkyTheme.defaultTheme
    }

    func setTheme(_ theme: SkyTheme) {
        defaults.set(theme.rawValue, forKey: SkyTheme.storageKey)
    }

    /// The theme to draw now, after the launch argument rules.
    func effectiveTheme(arguments: [String] = SkyTheme.processArguments) -> SkyTheme {
        SkyTheme.effective(stored: theme, arguments: arguments)
    }
}
