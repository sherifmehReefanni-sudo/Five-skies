import Foundation

/// The real Listen catalog: reciters and surah audio from the Quran Foundation Content API v4,
/// reached through the Five Skies relay.
///
/// - The reciter list is kept in memory for 1 hour. Nothing from the API is written to disk.
/// - Audio URLs point at the QF audio hosts and are played from there, never through the relay (D3).
actor RelayListenCatalog: ListenCatalog {
    static let reciterCacheSeconds: TimeInterval = 60 * 60
    /// `language=en` asks for English names; the API falls back to English when it has none.
    static let recitersPath = "/api/v4/resources/chapter_reciters?language=en"
    static let chapterRange = 1...114

    static func chapterAudioPath(reciterID: Int, chapter: Int) -> String {
        "/api/v4/chapter_recitations/\(reciterID)/\(chapter)"
    }

    private let client: any RelayFetching
    private let now: @Sendable () -> Date
    private var cachedReciters: [Reciter]?
    private var cachedAt: Date?
    private var inFlight: Task<[Reciter], Error>?

    init(client: any RelayFetching, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func reciters() async throws -> [Reciter] {
        if let cached = cachedReciters, let at = cachedAt, isFresh(at) {
            return cached
        }
        if let running = inFlight {
            return try await running.value
        }
        let client = self.client
        let task = Task<[Reciter], Error> {
            try await Self.loadReciters(client: client)
        }
        inFlight = task
        do {
            let list = try await task.value
            inFlight = nil
            cachedReciters = list
            cachedAt = now()
            return list
        } catch {
            inFlight = nil
            throw error
        }
    }

    func chapterAudio(reciterID: Int, chapter: Int) async throws -> ChapterAudio {
        guard reciterID > 0, Self.chapterRange.contains(chapter) else {
            throw ListenCatalogError.notFound
        }
        let response: ChapterAudioResponse
        do {
            response = try await client.get(
                relativePath: Self.chapterAudioPath(reciterID: reciterID, chapter: chapter),
                as: ChapterAudioResponse.self
            )
        } catch {
            throw Self.mapped(error)
        }
        guard let file = response.file(forChapter: chapter) else {
            throw ListenCatalogError.notFound
        }
        guard let url = ChapterAudioURL.resolve(file.audioUrl) else {
            throw ListenCatalogError.unexpected
        }
        return ChapterAudio(reciterID: reciterID, chapter: chapter, url: url, durationSeconds: file.durationSeconds)
    }

    /// Forgets the cached reciter list (for example after the relay switches to production).
    func clearCache() {
        cachedReciters = nil
        cachedAt = nil
    }

    private func isFresh(_ date: Date) -> Bool {
        let age = now().timeIntervalSince(date)
        return age >= 0 && age < Self.reciterCacheSeconds
    }

    private static func loadReciters(client: any RelayFetching) async throws -> [Reciter] {
        let response: ChapterRecitersResponse
        do {
            response = try await client.get(relativePath: recitersPath, as: ChapterRecitersResponse.self)
        } catch {
            throw mapped(error)
        }
        let list = response.listenReciters()
        guard !list.isEmpty else {
            throw ListenCatalogError.notAvailable
        }
        return list
    }

    /// Cancellation passes through untouched; everything else becomes a plain `ListenCatalogError`.
    private static func mapped(_ error: Error) -> Error {
        if error is CancellationError {
            return error
        }
        return ListenCatalogError.from(error)
    }
}
