import Foundation

/// The Start here path (plan L5): short surahs in a gentle order, starting with Al-Faatiha.
/// A manifest of surah numbers only. Names, ayah counts and text come from the bundled Quran data.
enum StartHerePath {
    /// Al-Faatiha, then the last three surahs (FABLE decision 2, Nov 28).
    static let opening = [1, 112, 113, 114]
    /// The other short surahs at the end, placed by `order(_:in:)`.
    static let shortSurahs = Array(103...111)
    static let teacherNote = "A common place to start. Your teacher may use another order."

    /// The whole path, worked out from the bundled text, never typed.
    static func surahs(in data: QuranData) -> [Int] {
        opening + order(shortSurahs, in: data)
    }

    /// Shortest first by ayah count, ties by word count (W2, on the text as shown), then the
    /// later surah first, as the path walks back from the end of the Quran.
    static func order(_ numbers: [Int], in data: QuranData) -> [Int] {
        let sizes: [Int: (ayahs: Int, words: Int)] = Dictionary(uniqueKeysWithValues: numbers.map { number in
            let ayahs = data.ayahs(inSura: number)
            let words = ayahs.reduce(0) { $0 + AyahWordSplitter.wordCount(in: $1.displayText) }
            return (number, (ayahs.count, words))
        })
        return numbers.sorted { left, right in
            let a = sizes[left] ?? (0, 0)
            let b = sizes[right] ?? (0, 0)
            if a.ayahs != b.ayahs { return a.ayahs < b.ayahs }
            if a.words != b.words { return a.words < b.words }
            return left > right
        }
    }

    /// The first surah of `path` that is not fully known, or nil when every step is known.
    /// `known` holds the surahs whose ayahs are all marked known.
    static func nextStep(known: Set<Int>, path: [Int]) -> Int? {
        path.first { !known.contains($0) }
    }

    /// Whether every ayah of a surah is known. A surah with no ayahs is never complete.
    static func isComplete(known: Int, ayahCount: Int) -> Bool {
        ayahCount > 0 && known >= ayahCount
    }

    /// "3 of 7 ayahs known", or "All 7 ayahs known" once the surah is complete.
    static func progressText(known: Int, ayahCount: Int) -> String {
        let shown = min(max(0, known), max(0, ayahCount))
        if isComplete(known: shown, ayahCount: ayahCount) {
            return "All \(ayahCount) ayahs known"
        }
        return "\(shown) of \(ayahCount) ayahs known"
    }

    /// The refs of every ayah in a surah.
    static func refs(sura: Int, ayahCount: Int) -> [AyahRef] {
        guard ayahCount > 0 else { return [] }
        return (1...ayahCount).map { AyahRef(sura: sura, aya: $0) }
    }
}
