import Foundation

/// Filters the sura list by number, transliterated name or English meaning.
/// Only the Latin names are folded for matching; nothing shown on screen is changed.
enum QuranSearch {
    static func filter(_ suras: [Sura], query: String) -> [Sura] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suras }
        if let number = Int(trimmed) {
            return suras.filter { $0.number == number }
        }
        let needle = fold(trimmed)
        guard !needle.isEmpty else { return [] }
        return suras.filter { sura in
            fold(sura.transliteratedName).contains(needle) || fold(sura.englishName).contains(needle)
        }
    }

    /// Lower case, without diacritics, keeping letters and digits only, so "al kahf" finds "Al-Kahf".
    static func fold(_ latin: String) -> String {
        let folded = latin.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var kept = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            kept.append(scalar)
        }
        return String(kept).lowercased()
    }
}
