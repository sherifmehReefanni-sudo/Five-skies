import Foundation

/// One word of an ayah as Quran Foundation lists it: its number, English meaning, transliteration
/// and recording. Never holds any Arabic from the API (Fable checkpoint 1, round E2.2).
struct AyahWordEntry: Equatable, Sendable {
    /// Quran Foundation's word number in the ayah, 1 based.
    let position: Int
    let meaning: String?
    let transliteration: String?
    let audioURL: URL?

    init(position: Int, meaning: String?, transliteration: String?, audioURL: URL?) {
        self.position = position
        self.meaning = meaning
        self.transliteration = transliteration
        self.audioURL = audioURL
    }
}

/// One row of the Words sheet.
struct AyahWordRow: Equatable, Identifiable, Sendable {
    let position: Int
    /// The word's slice of the stored ayah string, by its W2 range, with nothing trimmed or added.
    /// Nil when the ayah does not line up (W3), so no Arabic is shown.
    let arabic: String?
    let meaning: String?
    let transliteration: String?
    let audioURL: URL?

    var id: Int { position }
}

/// Builds the sheet's rows. Pure.
enum AyahWordsBuilder {
    /// - Parameters:
    ///   - storedText: exactly the string the reader draws for this ayah (`Ayah.displayText`).
    ///   - entries: Quran Foundation's words for the ayah, "end" markers already removed.
    /// - Returns: `aligned` is true only when our word count equals theirs and their word numbers
    ///   are exactly 1 to n (rule W3). Then each row carries its slice of `storedText`. Otherwise
    ///   the rows keep Quran Foundation's order and carry no Arabic.
    static func rows(storedText: String, entries: [AyahWordEntry]) -> (rows: [AyahWordRow], aligned: Bool) {
        let ranges = AyahWordSplitter.wordRanges(in: storedText)
        let positions = entries.map(\.position)
        let aligned = !entries.isEmpty
            && entries.count == ranges.count
            && Set(positions) == Set(1...ranges.count)

        guard aligned else {
            let rows = entries.map { entry in
                AyahWordRow(
                    position: entry.position,
                    arabic: nil,
                    meaning: entry.meaning,
                    transliteration: entry.transliteration,
                    audioURL: entry.audioURL
                )
            }
            return (rows: rows, aligned: false)
        }

        let scalars = storedText.unicodeScalars
        let rows = entries.sorted { $0.position < $1.position }.map { entry in
            let range = ranges[entry.position - 1]
            // The scalar view slices at exactly the range's bounds; the Character view could round a
            // bound to a grapheme edge and pull in a neighbouring scalar. Same stored scalars, unchanged.
            let slice = String(scalars[range])
            return AyahWordRow(
                position: entry.position,
                arabic: slice,
                meaning: entry.meaning,
                transliteration: entry.transliteration,
                audioURL: entry.audioURL
            )
        }
        return (rows: rows, aligned: true)
    }
}

/// Turns a word's `audio_url` into a URL the sheet can stream.
enum AyahWordAudioURL {
    /// Host for the relative word paths (`wbw/001_001_001.mp3`).
    static let relativeBaseString = "https://audio.qurancdn.com/"

    /// Full https URLs are kept, relative paths are resolved against `relativeBaseString`.
    /// Anything else (http, `//host`, other schemes, `..`) is ignored.
    static func resolve(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.contains("..") || text.contains("\\") || text.hasPrefix("//") {
            return nil
        }
        if text.lowercased().hasPrefix("https://") {
            guard let url = URL(string: text),
                  url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty
            else {
                return nil
            }
            return url
        }
        if text.contains("://") || URL(string: text)?.scheme != nil {
            return nil
        }
        while text.hasPrefix("/") {
            text.removeFirst()
        }
        guard !text.isEmpty,
              let base = URL(string: relativeBaseString),
              let url = URL(string: text, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              url.host == base.host
        else {
            return nil
        }
        return url
    }
}

// MARK: - Decoding

/// `GET verses/by_key/{sura}:{ayah}?words=true...`. Only the fields below are read; every
/// Arabic field the API sends (text_uthmani and the like) is never decoded.
struct AyahWordsResponse: Decodable, Sendable {
    struct Verse: Decodable, Sendable {
        let words: [AyahWordDTO]?

        private enum CodingKeys: String, CodingKey {
            case words
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            words = try? container.decodeIfPresent([AyahWordDTO].self, forKey: .words)
        }
    }

    let verse: Verse?

    /// The words without "end" markers, in the API's order. A word with no number takes its place in that order.
    var entries: [AyahWordEntry] {
        let words = (verse?.words ?? []).filter { !$0.isEnd }
        return words.enumerated().map { index, word in
            AyahWordEntry(
                position: word.position ?? index + 1,
                meaning: word.meaning,
                transliteration: word.transliteration,
                audioURL: AyahWordAudioURL.resolve(word.audioUrl)
            )
        }
    }
}

/// One element of `verse.words`. Keys arrive snake case and are converted by `RelayClient.makeDecoder()`.
/// Never throws: a field that is missing or of another type is nil.
struct AyahWordDTO: Decodable, Sendable {
    struct TextValue: Decodable, Sendable {
        let text: String?

        private enum CodingKeys: String, CodingKey {
            case text
        }

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            text = (try? container?.decodeIfPresent(String.self, forKey: .text)) ?? nil
        }
    }

    let position: Int?
    let charTypeName: String?
    let audioUrl: String?
    let meaning: String?
    let transliteration: String?

    private enum CodingKeys: String, CodingKey {
        case position
        case charTypeName
        case audioUrl
        case translation
        case transliteration
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        if let number = (try? container?.decodeIfPresent(Int.self, forKey: .position)) ?? nil {
            position = number
        } else if let raw = (try? container?.decodeIfPresent(String.self, forKey: .position)) ?? nil {
            position = Int(raw.trimmingCharacters(in: .whitespaces))
        } else {
            position = nil
        }
        charTypeName = (try? container?.decodeIfPresent(String.self, forKey: .charTypeName)) ?? nil
        audioUrl = (try? container?.decodeIfPresent(String.self, forKey: .audioUrl)) ?? nil
        let translation = (try? container?.decodeIfPresent(TextValue.self, forKey: .translation)) ?? nil
        meaning = Self.cleaned(translation?.text)
        let transliterationField = (try? container?.decodeIfPresent(TextValue.self, forKey: .transliteration)) ?? nil
        transliteration = Self.cleaned(transliterationField?.text)
    }

    var isEnd: Bool {
        charTypeName?.trimmingCharacters(in: .whitespaces).lowercased() == "end"
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
