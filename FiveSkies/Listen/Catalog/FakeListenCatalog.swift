import Foundation

/// Fixed made-up data for UI tests and previews (`-FSFakeListen`). No network.
/// The URLs point at example.com and are never meant to play.
struct FakeListenCatalog: ListenCatalog {
    static let sampleReciters: [Reciter] = [
        Reciter(id: 1, name: "Reciter One", style: "Murattal"),
        Reciter(id: 2, name: "Reciter Two", style: nil),
        Reciter(id: 3, name: "Reciter Three", style: "Mujawwad"),
    ]

    /// When set, every call throws this error (to show error states).
    let failure: ListenCatalogError?

    init(failure: ListenCatalogError? = nil) {
        self.failure = failure
    }

    func reciters() async throws -> [Reciter] {
        if let failure { throw failure }
        return Self.sampleReciters
    }

    func chapterAudio(reciterID: Int, chapter: Int) async throws -> ChapterAudio {
        if let failure { throw failure }
        guard Self.sampleReciters.contains(where: { $0.id == reciterID }),
              RelayListenCatalog.chapterRange.contains(chapter),
              let url = Self.sampleURL(reciterID: reciterID, chapter: chapter)
        else {
            throw ListenCatalogError.notFound
        }
        return ChapterAudio(
            reciterID: reciterID,
            chapter: chapter,
            url: url,
            durationSeconds: Double(60 + chapter * 5)
        )
    }

    static func sampleURL(reciterID: Int, chapter: Int) -> URL? {
        URL(string: "https://example.com/listen/reciter-\(reciterID)/\(String(format: "%03d", chapter)).mp3")
    }
}

/// Used when the app has no relay set up: every call throws `notAvailable`, and nothing touches the network.
struct UnavailableListenCatalog: ListenCatalog {
    func reciters() async throws -> [Reciter] {
        throw ListenCatalogError.notAvailable
    }

    func chapterAudio(reciterID: Int, chapter: Int) async throws -> ChapterAudio {
        throw ListenCatalogError.notAvailable
    }
}

/// Picks the catalog the app uses.
enum ListenCatalogFactory {
    /// Fake data under `-FSFakeListen`; the relay when Info.plist names one; otherwise a catalog
    /// that says recitations are not available. Inside unit tests and `-FSFixedPhase` runs
    /// `RelayConfig.fromBundle()` gives nil, so no network is ever used there.
    static func live(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> any ListenCatalog {
        if ListenLaunch.usesFakes(processInfo: processInfo) {
            return FakeListenCatalog()
        }
        guard let config = RelayConfig.fromBundle(bundle, processInfo: processInfo) else {
            return UnavailableListenCatalog()
        }
        return RelayListenCatalog(client: RelayClient(config: config))
    }
}
