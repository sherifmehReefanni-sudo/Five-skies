import Foundation

/// Folds Latin surah names, and what people type, into loose keys so that "baqarah",
/// "al-baqara" and "Al-Baqara" meet. Used only for matching; nothing shown on screen changes.
/// Works on the transliterated and English names only. Arabic letters are treated as separators.
enum QuranNameKey {
    /// The score of a key that matches exactly.
    static let exactScore = 1000

    /// The articles written before names in the metadata, as in Al-, An-, Ash-, and "the".
    private static let articles: Set<String> = [
        "al", "an", "ar", "as", "at", "ash", "ad", "adh", "az", "ath", "el", "the"
    ]

    /// Apostrophe-like marks, dropped so "An'aam" reads as "anaam".
    private static let apostrophes: Set<Unicode.Scalar> = [
        "'", "`", "\u{2018}", "\u{2019}", "\u{02BC}", "\u{02BB}", "\u{00B4}"
    ]

    private static let posix = Locale(identifier: "en_US_POSIX")

    // MARK: - Tokens

    /// Splits text into runs of ASCII letters (lower case) and runs of ASCII digits.
    /// Case, diacritics and width are folded, any Unicode decimal digit becomes an ASCII digit,
    /// apostrophes are dropped and every other character separates tokens. "p50" gives ["p", "50"].
    static func tokens(_ text: String) -> [String] {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: posix)
            .lowercased()
        var found: [String] = []
        var current = ""
        var currentIsDigits = false
        for scalar in folded.unicodeScalars {
            if apostrophes.contains(scalar) {
                continue
            }
            if let digit = asciiDigit(scalar) {
                if !currentIsDigits, !current.isEmpty {
                    found.append(current)
                    current = ""
                }
                currentIsDigits = true
                current.append(digit)
            } else if let letter = asciiLetter(scalar) {
                if currentIsDigits, !current.isEmpty {
                    found.append(current)
                    current = ""
                }
                currentIsDigits = false
                current.append(letter)
            } else if !current.isEmpty {
                found.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            found.append(current)
        }
        return found
    }

    /// True when the token is made of digits.
    static func isNumber(_ token: String) -> Bool {
        guard let first = token.unicodeScalars.first else { return false }
        return first.value >= 48 && first.value <= 57
    }

    private static func asciiDigit(_ scalar: Unicode.Scalar) -> Character? {
        guard scalar.properties.numericType == .decimal,
              let value = scalar.properties.numericValue,
              value >= 0, value <= 9
        else { return nil }
        return Character(String(Int(value)))
    }

    private static func asciiLetter(_ scalar: Unicode.Scalar) -> Character? {
        switch scalar.value {
        case 97...122:
            return Character(scalar)
        case 65...90:
            return Character(Unicode.Scalar(scalar.value + 32) ?? scalar)
        default:
            return nil
        }
    }

    // MARK: - Keys

    /// The loose keys for a name or a query: the whole name, and the name without a leading
    /// article, each with long vowels and doubled letters squashed. Empty when there are no letters.
    static func keys(_ text: String) -> [String] {
        let words = tokens(text).filter { !isNumber($0) }
        guard !words.isEmpty else { return [] }
        var joinedVariants = [words.joined()]
        if words.count > 1, articles.contains(words[0]) {
            joinedVariants.append(words.dropFirst().joined())
        } else if let unglued = withoutGluedArticle(words.joined()) {
            joinedVariants.append(unglued)
        }
        var result: [String] = []
        for variant in joinedVariants {
            let key = squash(variant)
            if !key.isEmpty, !result.contains(key) {
                result.append(key)
            }
        }
        return result
    }

    /// "albaqara" gives "baqara", "arrahman" gives "rahman", "ashshams" gives "shams".
    private static func withoutGluedArticle(_ joined: String) -> String? {
        let letters = Array(joined)
        if letters.count >= 5, joined.hasPrefix("al") {
            return String(letters.dropFirst(2))
        }
        if letters.count >= 6, joined.hasPrefix("ashsh") || joined.hasPrefix("adhdh") || joined.hasPrefix("athth") {
            return String(letters.dropFirst(3))
        }
        if letters.count >= 5, letters[0] == "a", letters[1] == letters[2], "nrstdz".contains(letters[1]) {
            return String(letters.dropFirst(2))
        }
        return nil
    }

    /// Squashes spelling differences: "ee" reads as "i", "oo" as "u", a "y" after the first
    /// letter as "i", doubled letters as one, and a final "ah" as "a".
    /// So "Yaseen", "yasin" and "ya sin" all give "yasin".
    static func squash(_ letters: String) -> String {
        let long = letters
            .replacingOccurrences(of: "ee", with: "i")
            .replacingOccurrences(of: "oo", with: "u")
        var chars = Array(long)
        for index in chars.indices where index > 0 && chars[index] == "y" {
            chars[index] = "i"
        }
        var squashed: [Character] = []
        for char in chars where squashed.last != char {
            squashed.append(char)
        }
        if squashed.count > 3, squashed.last == "h", squashed[squashed.count - 2] == "a" {
            squashed.removeLast()
        }
        return String(squashed)
    }

    // MARK: - Matching

    /// How well a query key matches a name key, or nil for no match. Higher is better.
    static func score(query: String, candidate: String) -> Int? {
        let queryLength = query.count
        let candidateLength = candidate.count
        if query == candidate {
            return exactScore
        }
        if queryLength >= 2, candidate.hasPrefix(query) {
            return 700 - (candidateLength - queryLength)
        }
        if queryLength >= 3, candidate.contains(query) {
            return 500 - (candidateLength - queryLength)
        }
        if queryLength >= 4 {
            let limit = queryLength >= 7 ? 2 : 1
            let distance = editDistance(query, candidate, limit: limit)
            if distance <= limit {
                return 300 - 50 * distance
            }
        }
        return nil
    }

    /// The suras a query matches by transliterated or English name, best first,
    /// equal scores in sura order.
    static func rank(_ query: String, in suras: [Sura]) -> [(sura: Sura, score: Int)] {
        let queryKeys = keys(query)
        guard !queryKeys.isEmpty else { return [] }
        var ranked: [(sura: Sura, score: Int)] = []
        for sura in suras {
            let nameKeys = keys(sura.transliteratedName) + keys(sura.englishName)
            var best: Int?
            for queryKey in queryKeys {
                for nameKey in nameKeys {
                    if let value = score(query: queryKey, candidate: nameKey), value > (best ?? Int.min) {
                        best = value
                    }
                }
            }
            if let best {
                ranked.append((sura: sura, score: best))
            }
        }
        ranked.sort { lhs, rhs in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.sura.number < rhs.sura.number
        }
        return ranked
    }

    /// True when a loose key of the query appears inside a loose key of the sura's names.
    /// Queries shorter than three letters never match this way.
    static func looselyContains(_ queryKeys: [String], sura: Sura) -> Bool {
        let usable = queryKeys.filter { $0.count >= 3 }
        guard !usable.isEmpty else { return false }
        let nameKeys = keys(sura.transliteratedName) + keys(sura.englishName)
        return usable.contains { queryKey in
            nameKeys.contains { $0.contains(queryKey) }
        }
    }

    /// Levenshtein distance on ASCII keys, giving up early once it is past `limit`.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        if abs(a.count - b.count) > limit {
            return limit + 1
        }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit {
                return limit + 1
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
