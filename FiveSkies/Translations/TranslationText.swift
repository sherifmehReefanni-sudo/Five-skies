import Foundation

/// Pure helpers for showing translations. Quran Foundation requires the text to be shown
/// unmodified, so the only change made for display is removing footnote markers.
enum TranslationText {
    private static let footnotePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: "<sup\\b[^>]*>.*?</sup>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    /// Removes footnote markup such as `<sup foot_note=123>1</sup>`, tags and contents,
    /// and leaves every other character exactly as it was.
    static func removingFootnotes(_ text: String) -> String {
        guard text.range(of: "<sup", options: .caseInsensitive) != nil, let regex = footnotePattern else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    /// "Translation: <name> by <author>. Provided by Quran Foundation."
    static func attribution(name: String, authorName: String?) -> String {
        if let author = authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            return "Translation: \(name) by \(author). Provided by Quran Foundation."
        }
        return "Translation: \(name). Provided by Quran Foundation."
    }

    static func isEnglish(_ languageName: String?) -> Bool {
        languageName?.trimmingCharacters(in: .whitespaces).lowercased() == "english"
    }

    /// The translation to suggest when none is selected: an English one named "Clear Quran",
    /// else one named "Saheeh International", else none. Never by numeric id.
    static func suggestion(in catalog: [TranslationInfo]) -> TranslationInfo? {
        let english = catalog.filter { isEnglish($0.languageName) }
        for needle in ["Clear Quran", "Saheeh International"] {
            if let match = english.first(where: { $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return match
            }
        }
        return nil
    }

    // MARK: - Transliteration (D6: its own text, not a translation)

    /// Quran Foundation lists the transliteration among the translations. It is found by name
    /// or slug; this id is only a tie breaker between entries that already match by name or slug.
    static let knownTransliterationID = 57

    static func isTransliteration(name: String?, slug: String?) -> Bool {
        [name, slug].contains(where: { value in
            value?.range(of: "translit", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        })
    }

    static func isTransliteration(_ info: TranslationInfo) -> Bool {
        isTransliteration(name: info.name, slug: info.slug)
    }

    /// The transliteration entry of the catalog: an entry whose name or slug contains "translit",
    /// English first, then the known id, then the lowest id. Nil when the catalog has none.
    static func transliterationEntry(in catalog: [TranslationInfo]) -> TranslationInfo? {
        let matches = catalog.filter { isTransliteration($0) }
        guard !matches.isEmpty else { return nil }
        let english = matches.filter { isEnglish($0.languageName) }
        let pool = english.isEmpty ? matches : english
        if let known = pool.first(where: { $0.id == knownTransliterationID }) {
            return known
        }
        return pool.min { $0.id < $1.id }
    }

    /// The catalog the translation picker shows: everything except transliterations.
    static func pickerCatalog(_ catalog: [TranslationInfo]) -> [TranslationInfo] {
        catalog.filter { !isTransliteration($0) }
    }

    private static func isPlainTransliterationName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare("Transliteration", options: [.caseInsensitive]) == .orderedSame
    }

    private static func trimmedAuthor(_ authorName: String?) -> String? {
        guard let author = authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty else {
            return nil
        }
        return author
    }

    /// The footer line, for example "Transliteration provided by Quran Foundation."
    static func transliterationAttribution(name: String, authorName: String?) -> String {
        let author = trimmedAuthor(authorName)
        if isPlainTransliterationName(name) {
            if let author {
                return "Transliteration by \(author). Provided by Quran Foundation."
            }
            return "Transliteration provided by Quran Foundation."
        }
        if let author {
            return "Transliteration: \(name) by \(author). Provided by Quran Foundation."
        }
        return "Transliteration: \(name). Provided by Quran Foundation."
    }

    /// The short source under the toggle, for example "Quran Foundation".
    static func transliterationSource(name: String, authorName: String?) -> String {
        var parts: [String] = []
        if !isPlainTransliterationName(name) {
            parts.append(name)
        }
        if let author = trimmedAuthor(authorName) {
            parts.append(author)
        }
        parts.append("Quran Foundation")
        return parts.joined(separator: ", ")
    }

    /// A language section of the picker.
    struct LanguageGroup: Identifiable, Equatable {
        let language: String
        let translations: [TranslationInfo]
        var id: String { language }
    }

    /// Groups by language, English first, then the others alphabetically; names sorted inside.
    static func groupedByLanguage(_ catalog: [TranslationInfo]) -> [LanguageGroup] {
        var buckets: [String: [TranslationInfo]] = [:]
        for info in catalog {
            buckets[displayLanguage(info.languageName), default: []].append(info)
        }
        let groups: [LanguageGroup] = buckets.map { entry in
            LanguageGroup(
                language: entry.key,
                translations: entry.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            )
        }
        return groups.sorted { lhs, rhs in
            let lhsEnglish = lhs.language == "English"
            let rhsEnglish = rhs.language == "English"
            if lhsEnglish != rhsEnglish {
                return lhsEnglish
            }
            return lhs.language.localizedCaseInsensitiveCompare(rhs.language) == .orderedAscending
        }
    }

    /// "english" becomes "English"; a missing language becomes "Other".
    static func displayLanguage(_ languageName: String?) -> String {
        guard let raw = languageName?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return "Other"
        }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
