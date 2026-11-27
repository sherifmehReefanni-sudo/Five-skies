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
