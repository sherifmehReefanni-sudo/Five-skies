import Foundation

/// The Start here path (plan L5): short surahs in a gentle order, starting with Al-Faatiha.
/// A manifest of surah numbers only. Names, ayah counts and text come from the bundled Quran data.
enum StartHerePath {
    /// Al-Faatiha, the last three surahs, then the other short ones at the end of the Quran.
    static let surahs = [1, 112, 113, 114, 111, 110, 109, 108, 107, 106, 105, 104, 103]

    /// The first surah on the path that is not fully known, or nil when every step is known.
    /// `known` holds the surahs whose ayahs are all marked known.
    static func nextStep(known: Set<Int>) -> Int? {
        surahs.first { !known.contains($0) }
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
