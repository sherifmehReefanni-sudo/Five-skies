import Foundation

// Shared contracts for the Listen tab (Phase B, round B1). Owned by the lead.
// Builders: Audio/ uses these types, Catalog/ produces them, UI/ shows them.
// No reciter names are typed in code: they come from the Quran Foundation API at run time.

/// A reciter as the Quran Foundation API lists it.
struct Reciter: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    /// The name exactly as the API gives it, shown with every recitation (D9).
    let name: String
    /// For example "Murattal", when the API gives one.
    let style: String?
}

/// Where one surah's full recitation can be streamed from.
struct ChapterAudio: Equatable, Sendable {
    let reciterID: Int
    let chapter: Int
    /// The file on the Quran Foundation hosts. Played straight from there, never through the relay (D3).
    let url: URL
    let durationSeconds: Double?
}

/// What the player is playing, with the credit line every player shows (D9).
struct NowPlayingItem: Equatable, Sendable {
    let reciter: Reciter
    let chapter: Int
    /// The surah name in English letters, from the bundled metadata.
    let chapterName: String
    let audio: ChapterAudio

    var credit: String {
        "\(reciter.name) \u{00B7} Quran Foundation"
    }
}

/// Where the player is.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}

/// Looks up reciters and surah audio. `RelayListenCatalog` (Catalog/) is the real one;
/// `FakeListenCatalog` (Catalog/) serves fixed test data and is used with `-FSFakeListen`.
protocol ListenCatalog: Sendable {
    func reciters() async throws -> [Reciter]
    func chapterAudio(reciterID: Int, chapter: Int) async throws -> ChapterAudio
}

/// The `-FSFakeListen` testing hook: fake catalog and a simulated player, no network, no audio.
enum ListenLaunch {
    static let fakeArgument = "-FSFakeListen"

    static func usesFakes(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(fakeArgument)
    }
}
