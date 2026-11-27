import Foundation

/// Finds the ayah and word playing at a moment, by binary search over timings sorted by start.
/// Pure functions, so `ListenPlayer` can call them on every position update.
enum ListenTimingLookup {
    /// The index in `ayahs` of the ayah playing at `seconds`, or nil in a gap, before the first or after the last.
    /// `ayahs` must be sorted by start (see `prepared`). If two overlap, the later one wins.
    static func ayahIndex(at seconds: Double, in ayahs: [AyahTiming]) -> Int? {
        guard seconds.isFinite,
              let index = lastIndex(startingAtOrBefore: seconds, count: ayahs.count, start: { ayahs[$0].start })
        else { return nil }
        return seconds < ayahs[index].end ? index : nil
    }

    /// The Quran Foundation word position playing at `seconds`, or nil between words.
    /// `words` must be sorted by start.
    static func wordPosition(at seconds: Double, in words: [WordTiming]) -> Int? {
        guard seconds.isFinite,
              let index = lastIndex(startingAtOrBefore: seconds, count: words.count, start: { words[$0].start })
        else { return nil }
        return seconds < words[index].end ? words[index].position : nil
    }

    /// Checks timings before the player uses them: they must be for this reciter and surah,
    /// times must be finite with the end after the start, and ayahs and words are sorted by start.
    /// Nil when nothing usable is left.
    static func prepared(_ timings: SurahTimings, reciterID: Int, chapter: Int) -> SurahTimings? {
        guard timings.reciterID == reciterID, timings.chapter == chapter else { return nil }
        let ayahs = timings.ayahs
            .filter { isValid(start: $0.start, end: $0.end) }
            .map { ayah in
                AyahTiming(
                    ayah: ayah.ayah,
                    start: ayah.start,
                    end: ayah.end,
                    words: ayah.words
                        .filter { isValid(start: $0.start, end: $0.end) }
                        .sorted { $0.start < $1.start }
                )
            }
            .sorted { $0.start < $1.start }
        guard !ayahs.isEmpty else { return nil }
        return SurahTimings(reciterID: reciterID, chapter: chapter, ayahs: ayahs)
    }

    private static func isValid(start: Double, end: Double) -> Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start
    }

    /// The last index whose start is at or before `seconds`, in O(log n).
    private static func lastIndex(startingAtOrBefore seconds: Double, count: Int, start: (Int) -> Double) -> Int? {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if start(middle) <= seconds {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : low - 1
    }
}

/// One remembered spot in a surah, kept under `ListenPlayer.resumeKey`.
struct ListenResumeEntry: Codable, Equatable, Sendable {
    let reciterID: Int
    let chapter: Int
    let seconds: Double
    /// The surah length when it was saved, zero if not known.
    let duration: Double
}
