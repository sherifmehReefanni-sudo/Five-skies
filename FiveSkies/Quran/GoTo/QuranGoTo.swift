import Foundation

/// One row under the Go to field: where it goes and how it reads.
struct QuranGoToSuggestion: Identifiable, Hashable {
    let target: QuranReaderTarget
    let title: String
    let detail: String

    var id: String { "\(target.sura):\(target.aya ?? 0)" }
}

/// What the Go to field makes of the text typed so far.
enum QuranGoToResult: Equatable {
    /// One place, with a short label saying where.
    case target(QuranReaderTarget, label: String)
    /// Several surahs match the name equally well, best first.
    case suggestions([QuranGoToSuggestion])
    case nothing

    /// Where Go takes you: the one place, or the best suggestion.
    var destination: QuranReaderTarget? {
        switch self {
        case .target(let target, _):
            return target
        case .suggestions(let suggestions):
            return suggestions.first?.target
        case .nothing:
            return nil
        }
    }
}

/// Reads "2:255", "2 255", "2.255", "surah 2", "2", surah names in English letters ("baqara",
/// "al-baqarah", "ya sin"), English meanings ("the cow"), a name and an ayah ("yasin 12"),
/// "page 50" or "p50", and "juz 30" or "j30". Case, spaces and Unicode digits are forgiven.
/// An ayah past the end of a surah goes to its last ayah and the label says so.
enum QuranGoTo {
    static let hint = "2:255, Yasin, page 50, juz 30"
    static let maxSuggestions = 6

    private static let surahWords: Set<String> = ["surah", "sura", "surat", "soorah", "chapter"]
    private static let pageWords: Set<String> = ["page", "pg", "p"]
    private static let juzWords: Set<String> = ["juz", "j", "para"]

    static func parse(_ text: String, data: QuranData) -> QuranGoToResult {
        var tokens = QuranNameKey.tokens(text)
        guard let first = tokens.first else { return .nothing }

        if !QuranNameKey.isNumber(first) {
            if pageWords.contains(first) {
                guard tokens.count == 2 else { return .nothing }
                return page(tokens[1], data: data)
            }
            if juzWords.contains(first) {
                guard tokens.count == 2 else { return .nothing }
                return juz(tokens[1], data: data)
            }
            let shortSurahWord = first == "s" && tokens.count > 1 && QuranNameKey.isNumber(tokens[1])
            if surahWords.contains(first) || shortSurahWord {
                tokens.removeFirst()
                guard !tokens.isEmpty else { return .nothing }
            }
        }

        if tokens.allSatisfy(QuranNameKey.isNumber) {
            switch tokens.count {
            case 1:
                return surah(tokens[0], ayah: nil, data: data)
            case 2:
                return surah(tokens[0], ayah: tokens[1], data: data)
            default:
                return .nothing
            }
        }

        // A name, maybe followed by an ayah number.
        var ayah: Int?
        if tokens.count > 1, let last = tokens.last, QuranNameKey.isNumber(last) {
            guard let value = number(last), value >= 1 else { return .nothing }
            ayah = value
            tokens.removeLast()
        }
        guard !tokens.contains(where: QuranNameKey.isNumber) else { return .nothing }
        return named(tokens.joined(separator: " "), ayah: ayah, data: data)
    }

    // MARK: - Forms

    private static func surah(_ suraToken: String, ayah ayahToken: String?, data: QuranData) -> QuranGoToResult {
        guard let suraNumber = number(suraToken), let sura = data.sura(suraNumber) else { return .nothing }
        guard let ayahToken else {
            return .target(QuranReaderTarget(sura: sura.number, aya: nil), label: surahLabel(sura))
        }
        guard let ayah = number(ayahToken), ayah >= 1 else { return .nothing }
        return ayahResult(sura, ayah: ayah)
    }

    private static func page(_ token: String, data: QuranData) -> QuranGoToResult {
        guard let page = number(token), page >= 1, page <= data.pageStarts.count else { return .nothing }
        let start = data.pageStarts[page - 1]
        guard let sura = data.sura(start.sura) else { return .nothing }
        return .target(
            QuranReaderTarget(sura: start.sura, aya: start.aya),
            label: "Page \(page), \(sura.transliteratedName), ayah \(start.aya)"
        )
    }

    private static func juz(_ token: String, data: QuranData) -> QuranGoToResult {
        guard let juz = number(token), juz >= 1, juz <= data.juzStarts.count else { return .nothing }
        let start = data.juzStarts[juz - 1]
        guard let sura = data.sura(start.sura) else { return .nothing }
        return .target(
            QuranReaderTarget(sura: start.sura, aya: start.aya),
            label: "Juz \(juz), \(sura.transliteratedName), ayah \(start.aya)"
        )
    }

    private static func named(_ query: String, ayah: Int?, data: QuranData) -> QuranGoToResult {
        let ranked = QuranNameKey.rank(query, in: data.suras)
        guard let top = ranked.first else { return .nothing }
        let isClearWinner = ranked.count == 1
            || (top.score == QuranNameKey.exactScore && ranked[1].score < QuranNameKey.exactScore)
        if isClearWinner {
            if let ayah {
                return ayahResult(top.sura, ayah: ayah)
            }
            return .target(QuranReaderTarget(sura: top.sura.number, aya: nil), label: surahLabel(top.sura))
        }
        let suggestions = ranked.prefix(maxSuggestions).map { entry in
            suggestion(entry.sura, ayah: ayah)
        }
        return .suggestions(Array(suggestions))
    }

    // MARK: - Labels

    private static func ayahResult(_ sura: Sura, ayah: Int) -> QuranGoToResult {
        if ayah > sura.ayahCount {
            return .target(
                QuranReaderTarget(sura: sura.number, aya: sura.ayahCount),
                label: "\(sura.transliteratedName) has \(sura.ayahCount) ayahs. Going to ayah \(sura.ayahCount)."
            )
        }
        return .target(
            QuranReaderTarget(sura: sura.number, aya: ayah),
            label: "\(sura.transliteratedName), ayah \(ayah)"
        )
    }

    private static func surahLabel(_ sura: Sura) -> String {
        "Surah \(sura.number), \(sura.transliteratedName)"
    }

    private static func suggestion(_ sura: Sura, ayah: Int?) -> QuranGoToSuggestion {
        let detail = "Surah \(sura.number) · \(sura.englishName) · \(sura.ayahCount) ayahs"
        guard let ayah else {
            return QuranGoToSuggestion(
                target: QuranReaderTarget(sura: sura.number, aya: nil),
                title: sura.transliteratedName,
                detail: detail
            )
        }
        let clamped = min(ayah, sura.ayahCount)
        return QuranGoToSuggestion(
            target: QuranReaderTarget(sura: sura.number, aya: clamped),
            title: "\(sura.transliteratedName), ayah \(clamped)",
            detail: detail
        )
    }

    /// A whole number of at most six digits after leading zeros, so nothing can overflow.
    private static func number(_ token: String) -> Int? {
        guard QuranNameKey.isNumber(token) else { return nil }
        let digits = token.drop(while: { $0 == "0" })
        guard digits.count <= 6 else { return nil }
        return digits.isEmpty ? 0 : Int(digits)
    }
}
