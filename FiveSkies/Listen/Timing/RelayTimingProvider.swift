import Foundation

/// Ayah and word timings from Quran Foundation (`chapter_recitations` with `segments=true`),
/// reached through the Five Skies relay.
///
/// - Fetched when a surah plays and held in memory only: the last `cacheLimit` surahs, each for at
///   most `maxAge` (24 hours). Nothing is ever written to disk from this path; surahs saved for
///   offline get their timings through Content Sync (docs/PHASE_B_PLAN.md).
/// - Returns nil on any failure; the player then greys its timing features. Failures are not
///   remembered, so the next play tries again.
actor RelayTimingProvider: SurahTimingProviding {
    struct Key: Hashable, Sendable {
        let reciterID: Int
        let chapter: Int
    }

    static let cacheLimit = 10
    /// An entry older than this is dropped and fetched again.
    static let maxAge: TimeInterval = 24 * 60 * 60
    static let chapterRange = 1...114

    static func path(reciterID: Int, chapter: Int) -> String {
        "/api/v4/chapter_recitations/\(reciterID)/\(chapter)?segments=true"
    }

    private let client: any RelayFetching
    private var cache: [Key: SurahTimings] = [:]
    private var storedAt: [Key: Date] = [:]
    private let now: @Sendable () -> Date
    /// Cached keys, least recently used first.
    private var recent: [Key] = []
    private var inFlight: [Key: Task<SurahTimings?, Never>] = [:]

    init(client: any RelayFetching, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    func timings(reciterID: Int, chapter: Int) async -> SurahTimings? {
        guard reciterID > 0, Self.chapterRange.contains(chapter) else { return nil }
        let key = Key(reciterID: reciterID, chapter: chapter)
        if let hit = cache[key] {
            if let stored = storedAt[key], now().timeIntervalSince(stored) <= Self.maxAge, now() >= stored {
                touch(key)
                return hit
            }
            drop(key)
        }
        if let running = inFlight[key] {
            return await running.value
        }
        let client = self.client
        let task = Task<SurahTimings?, Never> {
            await Self.load(client: client, reciterID: reciterID, chapter: chapter)
        }
        inFlight[key] = task
        let loaded = await task.value
        inFlight[key] = nil
        if let loaded {
            store(loaded, for: key)
        }
        return loaded
    }

    /// The cached surahs, least recently used first (for tests).
    func cachedKeys() -> [Key] {
        recent
    }

    func clearCache() {
        cache = [:]
        storedAt = [:]
        recent = []
    }

    private func drop(_ key: Key) {
        cache[key] = nil
        storedAt[key] = nil
        recent.removeAll { $0 == key }
    }

    private func touch(_ key: Key) {
        recent.removeAll { $0 == key }
        recent.append(key)
    }

    private func store(_ timings: SurahTimings, for key: Key) {
        cache[key] = timings
        storedAt[key] = now()
        touch(key)
        while recent.count > Self.cacheLimit {
            let oldest = recent.removeFirst()
            cache[oldest] = nil
            storedAt[oldest] = nil
        }
    }

    private static func load(client: any RelayFetching, reciterID: Int, chapter: Int) async -> SurahTimings? {
        do {
            let response = try await client.get(
                relativePath: path(reciterID: reciterID, chapter: chapter),
                as: ChapterTimingResponse.self
            )
            return response.surahTimings(reciterID: reciterID, chapter: chapter)
        } catch {
            return nil
        }
    }
}

/// Picks the timing provider the app uses. Nil means no timings: the player keeps its
/// timing options greyed out. Inside unit tests and `-FSFixedPhase` runs `RelayConfig.fromBundle()`
/// gives nil, so no network is ever used there. Under `-FSFakeListen` this gives nil too;
/// `FakeSurahTimingProvider` is there for a UI test that wants a moving highlight.
enum SurahTimingFactory {
    static func live(processInfo: ProcessInfo = .processInfo, bundle: Bundle = .main) -> (any SurahTimingProviding)? {
        if ListenLaunch.usesFakes(processInfo: processInfo) {
            return nil
        }
        guard let config = RelayConfig.fromBundle(bundle, processInfo: processInfo) else {
            return nil
        }
        return RelayTimingProvider(client: RelayClient(config: config))
    }
}

/// Made-up, evenly spaced timings for UI tests and previews. No network, no Quran text:
/// `wordCounts` gives the number of words in each ayah of a surah (from `FollowAlongText`),
/// and every ayah gets exactly that many words, so every ayah aligns at word level.
struct FakeSurahTimingProvider: SurahTimingProviding {
    let wordCounts: @Sendable (Int) async -> [Int]?
    /// Matches `FakeListenCatalog` (60 + 5 seconds per surah number).
    let duration: @Sendable (Int) -> Double

    init(
        wordCounts: @escaping @Sendable (Int) async -> [Int]?,
        duration: @escaping @Sendable (Int) -> Double = { Double(60 + $0 * 5) }
    ) {
        self.wordCounts = wordCounts
        self.duration = duration
    }

    func timings(reciterID: Int, chapter: Int) async -> SurahTimings? {
        guard let counts = await wordCounts(chapter), !counts.isEmpty else { return nil }
        let total = duration(chapter)
        guard total.isFinite, total > 0 else { return nil }
        let ayahLength = total / Double(counts.count)
        var ayahs: [AyahTiming] = []
        for (index, count) in counts.enumerated() {
            let start = ayahLength * Double(index)
            let end = start + ayahLength
            let words = max(0, count)
            let step = words > 0 ? ayahLength / Double(words) : 0
            let wordTimings = (0..<words).map { word in
                WordTiming(position: word + 1, start: start + step * Double(word), end: start + step * Double(word + 1))
            }
            ayahs.append(AyahTiming(ayah: index + 1, start: start, end: end, words: wordTimings))
        }
        return SurahTimings(reciterID: reciterID, chapter: chapter, ayahs: ayahs)
    }
}
