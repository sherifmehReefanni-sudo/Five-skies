import Foundation

/// Splits a stored ayah into word ranges (plan rule W2), without changing the string (rule W1).
///
/// - Works on Unicode scalars, because in the Tanzil text a pause mark follows a space as its own
///   token, and a space plus a combining mark is one Character to Swift.
/// - Splits on whitespace scalars. A token is a word only if it holds at least one Arabic letter
///   (general category "other letter" inside the Arabic blocks). Decided by scalar values, no typed Arabic.
/// - A token with no letter (a pause mark, the sajdah sign, the rub el hizb sign) is joined to the
///   word before it: that word's range is extended through it. A sign-only token before the first
///   word (the rub el hizb sign that starts some ayahs) belongs to no range and is never highlighted.
/// - The ranges index the very string passed in. Nothing is built, edited or re-joined.
enum AyahWordSplitter {
    /// Unicode blocks of the Arabic script, as code point ranges.
    private static let arabicBlocks: [ClosedRange<UInt32>] = [
        0x0600...0x06FF,
        0x0750...0x077F,
        0x0870...0x08FF,
        0xFB50...0xFDFF,
        0xFE70...0xFEFF,
    ]

    /// A base letter of the Arabic script. Marks (harakat, pause marks), signs, digits and
    /// the tatweel are not letters.
    static func isArabicLetter(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.generalCategory == .otherLetter else { return false }
        let value = scalar.value
        return arabicBlocks.contains { $0.contains(value) }
    }

    static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace
    }

    /// The word ranges of `text`, in reading order, over `text` itself.
    static func wordRanges(in text: String) -> [Range<String.Index>] {
        let scalars = text.unicodeScalars
        var ranges: [Range<String.Index>] = []
        var tokenStart: String.Index?
        var tokenHasLetter = false

        func finishToken(_ start: String.Index, _ end: String.Index) {
            if tokenHasLetter {
                ranges.append(start..<end)
            } else if let last = ranges.last {
                // Sign-only token: extend the word before it through the sign.
                ranges[ranges.count - 1] = last.lowerBound..<end
            }
            // A sign-only token before any word is left outside every range.
        }

        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if isSeparator(scalar) {
                if let start = tokenStart {
                    finishToken(start, index)
                    tokenStart = nil
                }
            } else {
                if tokenStart == nil {
                    tokenStart = index
                    tokenHasLetter = false
                }
                if isArabicLetter(scalar) {
                    tokenHasLetter = true
                }
            }
            index = scalars.index(after: index)
        }
        if let start = tokenStart {
            finishToken(start, scalars.endIndex)
        }
        return ranges
    }

    /// The number of words in `text`, by the same rule.
    static func wordCount(in text: String) -> Int {
        wordRanges(in: text).count
    }
}

/// One ayah as the reader shows it, with its word ranges.
///
/// `text` is `Ayah.displayText`: the stored string, except that on ayah 1 of every surah but 1 and 9
/// the reader shows the basmala as a separate header (`Ayah.splitBasmala`) and this is the rest.
/// The ranges index `text`, so the reader must draw this same `text` (not a fresh `displayText`)
/// when it highlights. The basmala header is never part of any range (plan rule W5).
struct FollowAlongText: Equatable, Sendable {
    let sura: Int
    let ayah: Int
    let text: String
    /// Word 1 first. Index n - 1 holds word n.
    let wordRanges: [Range<String.Index>]
    /// True when the reader shows this ayah's basmala as a separate header line.
    let hasBasmalaHeader: Bool

    init(ayah: Ayah) {
        sura = ayah.sura
        self.ayah = ayah.number
        let shown = ayah.displayText
        text = shown
        wordRanges = AyahWordSplitter.wordRanges(in: shown)
        hasBasmalaHeader = ayah.basmala != nil
    }

    var wordCount: Int { wordRanges.count }

    /// The range of word `position` (1 based), or nil when there is no such word.
    func range(ofWord position: Int) -> Range<String.Index>? {
        guard position >= 1, position <= wordRanges.count else { return nil }
        return wordRanges[position - 1]
    }

    /// A range as Unicode scalar offsets from the start of `text`. Use these to find the same
    /// span in an `AttributedString` made from `text`, through its `unicodeScalars` view.
    func scalarOffsets(of range: Range<String.Index>) -> Range<Int> {
        let scalars = text.unicodeScalars
        let lower = scalars.distance(from: scalars.startIndex, to: range.lowerBound)
        let upper = scalars.distance(from: scalars.startIndex, to: range.upperBound)
        return lower..<upper
    }
}
