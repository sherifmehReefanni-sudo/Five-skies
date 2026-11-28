import SwiftUI

/// One ayah whose meaning matches a search, ready to show as a row.
struct TranslationSearchHit: Identifiable, Equatable, Sendable {
    let sura: Int
    let aya: Int
    /// About 120 characters of the translation around the first match, with "…" where it was cut.
    let snippet: String
    /// Character offsets into `snippet` of the first match, for bolding.
    let matchRange: Range<Int>

    var id: String { "\(sura):\(aya)" }

    var target: QuranReaderTarget {
        QuranReaderTarget(sura: sura, aya: aya)
    }
}

/// The downloaded translation folded once (lower case, no diacritics), in Quran order,
/// so each keystroke only scans and never refolds. Build it once per loaded translation.
struct TranslationSearchIndex: Sendable {
    struct Entry: Sendable {
        let sura: Int
        let aya: Int
        /// The display text, exactly as stored.
        let text: String
        /// `text` folded for matching.
        let folded: String
        /// For each unicode scalar of `folded`, the Character offset in `text` it came from.
        /// Nil when the two line up one to one (plain ASCII text).
        let originalOffsets: [Int]?
    }

    /// Sorted by sura, then ayah, as numbers.
    let entries: [Entry]

    init(verses: [String: String]) {
        var built: [Entry] = []
        built.reserveCapacity(verses.count)
        for (key, text) in verses {
            guard let ref = TranslationSearch.parseKey(key) else { continue }
            let fold = TranslationSearch.fold(text)
            built.append(Entry(sura: ref.sura, aya: ref.aya, text: text, folded: fold.folded, originalOffsets: fold.offsets))
        }
        built.sort { lhs, rhs in
            lhs.sura != rhs.sura ? lhs.sura < rhs.sura : lhs.aya < rhs.aya
        }
        entries = built
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Ayahs that contain every word of the query, in Quran order, at most `limit`.
    func search(_ query: String, limit: Int = 50) -> [TranslationSearchHit] {
        guard limit > 0, let words = TranslationSearch.queryWords(query) else { return [] }
        var hits: [TranslationSearchHit] = []
        for entry in entries {
            guard let match = Self.firstMatch(of: words, in: entry) else { continue }
            let cut = TranslationSearch.snippet(of: entry.text, match: match)
            hits.append(TranslationSearchHit(sura: entry.sura, aya: entry.aya, snippet: cut.text, matchRange: cut.match))
            if hits.count >= limit { break }
        }
        return hits
    }

    /// The earliest match among the words, as Character offsets in the entry's text,
    /// or nil when any word is missing.
    private static func firstMatch(of words: [String], in entry: Entry) -> Range<Int>? {
        var earliest: Range<String.Index>?
        for word in words {
            guard let found = entry.folded.range(of: word, options: .literal) else { return nil }
            if earliest == nil || found.lowerBound < earliest!.lowerBound {
                earliest = found
            }
        }
        guard let earliest else { return nil }
        let scalars = entry.folded.unicodeScalars
        let lower = scalars.distance(from: scalars.startIndex, to: earliest.lowerBound)
        let upper = scalars.distance(from: scalars.startIndex, to: earliest.upperBound)
        guard lower < upper else { return nil }
        guard let offsets = entry.originalOffsets else {
            return lower..<upper
        }
        guard upper <= offsets.count else { return nil }
        return offsets[lower]..<(offsets[upper - 1] + 1)
    }
}

/// Search in the meaning (E2.3): pure helpers, no state.
enum TranslationSearch {
    static let minimumQueryLength = 3
    static let snippetLength = 120
    static let ellipsis: Character = "\u{2026}"

    /// Convenience for a one-off search. Views should keep a `TranslationSearchIndex` instead.
    static func search(_ query: String, in verses: [String: String], limit: Int = 50) -> [TranslationSearchHit] {
        guard queryWords(query) != nil else { return [] }
        return TranslationSearchIndex(verses: verses).search(query, limit: limit)
    }

    /// "2:255" as numbers. Nil unless it is exactly two positive whole numbers around one colon.
    static func parseKey(_ key: String) -> (sura: Int, aya: Int)? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let sura = Int(parts[0]), let aya = Int(parts[1]),
              sura > 0, aya > 0
        else { return nil }
        return (sura, aya)
    }

    /// The folded, distinct words of the query, or nil when the trimmed query is under 3 characters.
    static func queryWords(_ query: String) -> [String]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return nil }
        var words: [String] = []
        for piece in fold(trimmed).folded.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(piece)
            if !word.isEmpty, !words.contains(word) {
                words.append(word)
            }
        }
        return words.isEmpty ? nil : words
    }

    /// Lower case without diacritics, curly quotes made straight. Also returns, for each
    /// scalar of the result, the Character offset in `text` it came from (nil when one to one).
    static func fold(_ text: String) -> (folded: String, offsets: [Int]?) {
        var folded = String.UnicodeScalarView()
        var offsets: [Int] = []
        offsets.reserveCapacity(text.utf8.count)
        var identity = true
        var characterOffset = 0
        for character in text {
            if character.isASCII {
                for scalar in character.unicodeScalars {
                    let value = scalar.value
                    if value >= 65, value <= 90 {
                        folded.append(Unicode.Scalar(UInt8(value + 32)))
                    } else {
                        folded.append(scalar)
                    }
                    if offsets.count != characterOffset { identity = false }
                    offsets.append(characterOffset)
                }
            } else {
                let piece = foldedPiece(character)
                for scalar in piece.unicodeScalars {
                    if offsets.count != characterOffset { identity = false }
                    folded.append(scalar)
                    offsets.append(characterOffset)
                }
                if piece.unicodeScalars.isEmpty { identity = false }
            }
            characterOffset += 1
        }
        if offsets.count != characterOffset { identity = false }
        return (String(folded), identity ? nil : offsets)
    }

    private static let foldLocale = Locale(identifier: "en_US_POSIX")

    private static func foldedPiece(_ character: Character) -> String {
        switch character {
        case "\u{2018}", "\u{2019}", "\u{02BC}":
            return "'"
        case "\u{201C}", "\u{201D}":
            return "\""
        default:
            return String(character)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale)
                .lowercased()
        }
    }

    /// About `maxLength` characters of `text` around `match` (Character offsets), cut on word
    /// boundaries, with "…" at each cut end. Returns the snippet and the match's offsets in it.
    static func snippet(of text: String, match: Range<Int>, maxLength: Int = snippetLength) -> (text: String, match: Range<Int>) {
        let chars = Array(text)
        let count = chars.count
        let lower = min(max(match.lowerBound, 0), count)
        let upper = min(max(match.upperBound, lower), count)
        guard count > maxLength else {
            return (text, lower..<upper)
        }

        var start = max(0, lower - maxLength / 3)
        var end = min(count, start + maxLength)
        if end == count {
            start = max(0, min(lower, count - maxLength))
        }
        end = max(end, upper)

        // Start: never inside a word.
        if start > 0, !chars[start - 1].isWhitespace, !chars[start].isWhitespace {
            var forward = start
            while forward < lower, !chars[forward].isWhitespace {
                forward += 1
            }
            if forward < lower {
                start = forward + 1
            } else {
                var back = start
                while back > 0, !chars[back - 1].isWhitespace {
                    back -= 1
                }
                start = back
            }
        }

        // End: never inside a word.
        if end < count, !chars[end - 1].isWhitespace, !chars[end].isWhitespace {
            var back = end
            while back > upper, !chars[back - 1].isWhitespace {
                back -= 1
            }
            if back > upper {
                end = back - 1
            } else {
                var forward = end
                while forward < count, !chars[forward].isWhitespace {
                    forward += 1
                }
                end = forward
            }
        }

        while start < lower, chars[start].isWhitespace {
            start += 1
        }
        while end > upper, chars[end - 1].isWhitespace {
            end -= 1
        }

        let cutStart = start > 0
        let cutEnd = end < count
        var result = cutStart ? String(ellipsis) : ""
        result += String(chars[start..<end])
        if cutEnd {
            result.append(ellipsis)
        }
        let shift = (cutStart ? 1 : 0) - start
        return (result, (lower + shift)..<(upper + shift))
    }

    /// The snippet with the match in bold gold. Only the English snippet is styled.
    static func attributedSnippet(_ hit: TranslationSearchHit) -> AttributedString {
        var attributed = AttributedString(hit.snippet)
        let characters = attributed.characters
        let range = hit.matchRange
        guard range.lowerBound >= 0, range.lowerBound < range.upperBound, range.upperBound <= characters.count else {
            return attributed
        }
        let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
        let upper = characters.index(characters.startIndex, offsetBy: range.upperBound)
        var style = AttributeContainer()
        style.foregroundColor = QuranPalette.gold
        style.inlinePresentationIntent = .stronglyEmphasized
        attributed[lower..<upper].mergeAttributes(style)
        return attributed
    }

    /// "Al-Baqara 2:255", or "2:255" when the name is not known.
    static func title(for hit: TranslationSearchHit, suraName: String?) -> String {
        let ref = "\(hit.sura):\(hit.aya)"
        guard let name = suraName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return ref
        }
        return "\(name) \(ref)"
    }
}

/// Rows for the Quran tab search: a caption, then one card per ayah whose meaning matches.
/// Each row is a List row (uses `quranListRow`), so place it straight inside the List.
struct TranslationSearchSection: View {
    let hits: [TranslationSearchHit]
    let translationName: String
    let suraName: (Int) -> String?
    let onOpen: (QuranReaderTarget) -> Void

    var body: some View {
        Group {
            MoreCaption(text: "In the meaning · \(translationName)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meaningSearchHeader")
                .quranListRow()

            if hits.isEmpty {
                Text("No ayahs mention that yet.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("meaningSearchEmpty")
                    .quranListRow()
            }

            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                let title = TranslationSearch.title(for: hit, suraName: suraName(hit.sura))
                Button {
                    onOpen(hit.target)
                } label: {
                    TranslationSearchHitLabel(title: title, snippet: TranslationSearch.attributedSnippet(hit))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(Text(verbatim: "\(title). \(hit.snippet)"))
                .accessibilityHint("Opens the reader at this ayah")
                .accessibilityIdentifier("meaningHit-\(index)")
                .quranListRow()
            }
        }
    }
}

/// One matching ayah: the sura name and verse key, then the snippet with the match in gold.
private struct TranslationSearchHitLabel: View {
    let title: String
    let snippet: AttributedString

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text(snippet)
                    .font(.subheadline)
                    .foregroundStyle(MorePalette.secondaryText)
                    .lineLimit(4)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 22)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// One quiet line under the surah results when no translation is loaded yet.
struct TranslationSearchPrompt: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.size")
                .font(.footnote.weight(.bold))
                .foregroundStyle(QuranPalette.gold)
                .accessibilityHidden(true)
            Text("Download a translation in Aa to search the meaning")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meaningSearchPrompt")
        .quranListRow()
    }
}
