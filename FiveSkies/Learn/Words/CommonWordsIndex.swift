import Foundation

/// Where a word form first appears: sura, ayah and its word number in that ayah (1 based, W2 split).
struct CommonWordOccurrence: Hashable, Comparable, Sendable {
    let sura: Int
    let aya: Int
    let wordPosition: Int

    var ref: AyahRef { AyahRef(sura: sura, aya: aya) }

    /// Quran order: sura, then ayah, then word.
    static func < (lhs: CommonWordOccurrence, rhs: CommonWordOccurrence) -> Bool {
        if lhs.sura != rhs.sura { return lhs.sura < rhs.sura }
        if lhs.aya != rhs.aya { return lhs.aya < rhs.aya }
        return lhs.wordPosition < rhs.wordPosition
    }
}

/// One written word form and how often it appears.
struct CommonWordEntry: Hashable, Identifiable, Sendable {
    /// 1 is the most frequent.
    let rank: Int
    /// The word's slice of the stored ayah string, by its W2 range, exactly as stored.
    let form: String
    let count: Int
    let firstOccurrence: CommonWordOccurrence

    var id: Int { rank }
}

/// Common words (plan L4), counted on the device from the bundled text. Pure.
///
/// Every ayah's `displayText` is split with `AyahWordSplitter` (rule W2). The counting key is the
/// word token as stored, with its vowel marks, without any sign-only token the splitter attached
/// to it (FABLE decision 1, Nov 28): a word with a pause sign counts as the same form. The key is
/// itself a slice of the stored string (the start of the word's range). Exact written forms, not
/// roots; vowel marks are never stripped. The basmala that
/// the reader shows as a header is not part of `displayText` and is not counted.
/// Ties are broken by first occurrence in Quran order, so the ranking is stable.
struct CommonWordsIndex: Sendable {
    /// The counting key of a word's W2 slice: its scalars up to the first separator, so an
    /// attached sign-only token is left out. Never changes or strips a scalar.
    static func formKey(_ slice: Substring.UnicodeScalarView) -> String {
        if let end = slice.firstIndex(where: AyahWordSplitter.isSeparator) {
            return String(slice[slice.startIndex..<end])
        }
        return String(slice)
    }

    static func formKey(_ slice: String) -> String {
        formKey(Substring(slice).unicodeScalars)
    }

    /// Rank order: rank 1 first.
    let entries: [CommonWordEntry]
    /// Every word counted, all forms together.
    let totalWordCount: Int
    /// `cumulativeCounts[n]` is the number of words covered by the top n forms. Index 0 is 0.
    private let cumulativeCounts: [Int]

    var distinctFormCount: Int { entries.count }

    init(data: QuranData) {
        self.init(ayahs: data.ayahsBySura.joined())
    }

    init<S: Sequence>(ayahs: S) where S.Element == Ayah {
        var slots: [String: Int] = [:]
        var forms: [String] = []
        var counts: [Int] = []
        var firsts: [CommonWordOccurrence] = []
        var total = 0

        for ayah in ayahs {
            let text = ayah.displayText
            let scalars = text.unicodeScalars
            let ranges = AyahWordSplitter.wordRanges(in: text)
            for (offset, range) in ranges.enumerated() {
                let form = Self.formKey(scalars[range])
                let here = CommonWordOccurrence(sura: ayah.sura, aya: ayah.number, wordPosition: offset + 1)
                total += 1
                if let slot = slots[form] {
                    counts[slot] += 1
                    if here < firsts[slot] {
                        firsts[slot] = here
                    }
                } else {
                    slots[form] = forms.count
                    forms.append(form)
                    counts.append(1)
                    firsts.append(here)
                }
            }
        }

        let order = forms.indices.sorted { left, right in
            if counts[left] != counts[right] {
                return counts[left] > counts[right]
            }
            return firsts[left] < firsts[right]
        }

        var built: [CommonWordEntry] = []
        built.reserveCapacity(order.count)
        var cumulative: [Int] = [0]
        cumulative.reserveCapacity(order.count + 1)
        var running = 0
        for (offset, slot) in order.enumerated() {
            built.append(
                CommonWordEntry(rank: offset + 1, form: forms[slot], count: counts[slot], firstOccurrence: firsts[slot])
            )
            running += counts[slot]
            cumulative.append(running)
        }

        entries = built
        totalWordCount = total
        cumulativeCounts = cumulative
    }

    /// The top `n` forms, fewer when there are not that many.
    func top(_ n: Int) -> [CommonWordEntry] {
        Array(entries.prefix(max(n, 0)))
    }

    /// How many of all the words are one of the top `n` forms.
    func coveredWordCount(top n: Int) -> Int {
        let clamped = min(max(n, 0), entries.count)
        return cumulativeCounts[clamped]
    }

    /// The share of all words (0 to 1) that are one of the top `n` forms. Our own arithmetic.
    func coverage(top n: Int) -> Double {
        guard totalWordCount > 0 else { return 0 }
        return Double(coveredWordCount(top: n)) / Double(totalWordCount)
    }

    /// The same share as a whole percent, rounded to the nearest (half away from zero).
    func coveragePercent(top n: Int) -> Int {
        Int((coverage(top: n) * 100).rounded())
    }
}

/// Builds the index once, off the main thread, and keeps it in memory for the app's run. Nothing stored.
@MainActor
final class CommonWordsIndexLoader {
    static let shared = CommonWordsIndexLoader()

    private var built: CommonWordsIndex?
    private var building: Task<CommonWordsIndex, Never>?

    func index(for data: QuranData) async -> CommonWordsIndex {
        if let built {
            return built
        }
        if let building {
            return await building.value
        }
        let task = Task.detached(priority: .userInitiated) { () -> CommonWordsIndex in
            CommonWordsIndex(data: data)
        }
        building = task
        let result = await task.value
        built = result
        building = nil
        return result
    }
}

/// The plain English lines of the common words screens. Pure, so tests can check them.
enum CommonWordsText {
    static let choices = [50, 100, 200, 500]
    static let defaultChoice = 100

    static let note = "Counted from the written forms in the text. Words from the same root are counted separately."
    static let creditLine = "Word meanings: Quran Foundation"
    static let notAlignedLine = "Meaning not available for this word yet"
    static let needsConnectionLine = "Meanings need a connection"

    static func number(_ value: Int, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale))
    }

    /// "These 100 words make up 29% of all the words in the Quran". Number and percent from the index.
    static func headline(index: CommonWordsIndex, top n: Int, locale: Locale = .current) -> String {
        let shown = min(max(n, 0), index.distinctFormCount)
        let percent = index.coveragePercent(top: shown)
        return "These \(number(shown, locale: locale)) words make up \(percent)% of all the words in the Quran"
    }

    /// "77,433 words in all, in 20,718 written forms".
    static func totals(index: CommonWordsIndex, locale: Locale = .current) -> String {
        "\(number(index.totalWordCount, locale: locale)) words in all, in \(number(index.distinctFormCount, locale: locale)) written forms"
    }

    static func appears(_ count: Int, locale: Locale = .current) -> String {
        count == 1 ? "appears 1 time" : "appears \(number(count, locale: locale)) times"
    }

    /// "Al-Baqara 2:5, word 3".
    static func example(suraName: String, occurrence: CommonWordOccurrence) -> String {
        "\(suraName) \(occurrence.sura):\(occurrence.aya), word \(occurrence.wordPosition)"
    }
}
