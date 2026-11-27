import Foundation

// Tolerant decoders for the two Quran Foundation Content API v4 answers the Listen tab reads.
// The relay decoder converts snake case keys, so `translated_name` arrives as `translatedName`.
// Every field is optional, unknown fields are ignored and a bad entry is skipped, never fatal.
// Nothing decoded here is written to disk (QF terms: offline copies only through Content Sync).

/// Decodes a value, or holds nil when that one value is malformed.
struct ListenCatalogLossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// An object like `{"name": "...", "language_name": "..."}`, also accepted as a plain string.
struct ListenCatalogNamedValue: Decodable, Equatable, Sendable {
    let name: String?
    let languageName: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case languageName
    }

    init(name: String?, languageName: String?) {
        self.name = name
        self.languageName = languageName
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            name = text
            languageName = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        languageName = try? container.decodeIfPresent(String.self, forKey: .languageName)
    }

    /// True when the value is labelled English, or carries no language label at all.
    var isEnglishOrUnlabelled: Bool {
        guard let label = languageName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !label.isEmpty else {
            return true
        }
        return label == "english" || label == "en"
    }
}

// MARK: - GET /resources/chapter_reciters

/// `{"reciters": [...]}`.
struct ChapterRecitersResponse: Decodable, Sendable {
    let reciters: [ChapterReciterDTO]

    private enum CodingKeys: String, CodingKey {
        case reciters
    }

    init(reciters: [ChapterReciterDTO]) {
        self.reciters = reciters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try? container.decodeIfPresent([ListenCatalogLossy<ChapterReciterDTO>].self, forKey: .reciters)
        reciters = (items ?? []).compactMap { $0.value }
    }

    /// The reciters the app can show, in the order the API gives them, without duplicate ids.
    func listenReciters() -> [Reciter] {
        var seen = Set<Int>()
        var result: [Reciter] = []
        for item in reciters {
            guard let reciter = item.reciter(), !seen.contains(reciter.id) else { continue }
            seen.insert(reciter.id)
            result.append(reciter)
        }
        return result
    }
}

/// One entry of `reciters`. Documented fields: id, reciter_id, name, beta, style, qirat, translated_name.
/// Only id, name, translated_name and style are read.
struct ChapterReciterDTO: Decodable, Sendable {
    let id: Int?
    let name: String?
    let translatedName: ListenCatalogNamedValue?
    let style: ListenCatalogNamedValue?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case translatedName
        case style
    }

    init(id: Int?, name: String?, translatedName: ListenCatalogNamedValue?, style: ListenCatalogNamedValue?) {
        self.id = id
        self.name = name
        self.translatedName = translatedName
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.listenFlexibleInt(forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        translatedName = try? container.decodeIfPresent(ListenCatalogNamedValue.self, forKey: .translatedName)
        style = try? container.decodeIfPresent(ListenCatalogNamedValue.self, forKey: .style)
    }

    /// The name to show: `translated_name.name` when it is in English, else `name`
    /// (which the docs describe as the English name). A name in Arabic script is never used.
    var englishName: String? {
        var candidates: [String?] = []
        if let translated = translatedName, translated.isEnglishOrUnlabelled {
            candidates.append(translated.name)
        }
        candidates.append(name)
        for candidate in candidates {
            if let clean = ListenCatalogText.cleaned(candidate), !ListenCatalogText.containsArabicScript(clean) {
                return clean
            }
        }
        return nil
    }

    /// For example "Murattal", when given and not in Arabic script.
    var styleName: String? {
        guard let clean = ListenCatalogText.cleaned(style?.name), !ListenCatalogText.containsArabicScript(clean) else {
            return nil
        }
        return clean
    }

    /// Nil when the entry has no usable id or no English name.
    func reciter() -> Reciter? {
        guard let id, id > 0, let display = englishName else { return nil }
        return Reciter(id: id, name: display, style: styleName)
    }
}

// MARK: - GET /chapter_recitations/{reciter_id}/{chapter_number}

/// `{"audio_file": {...}}`. Also reads `{"audio_files": [...]}` (the shape of the all chapters list).
struct ChapterAudioResponse: Decodable, Sendable {
    let audioFile: ChapterAudioFileDTO?
    let audioFiles: [ChapterAudioFileDTO]

    private enum CodingKeys: String, CodingKey {
        case audioFile
        case audioFiles
    }

    init(audioFile: ChapterAudioFileDTO?, audioFiles: [ChapterAudioFileDTO] = []) {
        self.audioFile = audioFile
        self.audioFiles = audioFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioFile = try? container.decodeIfPresent(ChapterAudioFileDTO.self, forKey: .audioFile)
        let items = try? container.decodeIfPresent([ListenCatalogLossy<ChapterAudioFileDTO>].self, forKey: .audioFiles)
        audioFiles = (items ?? []).compactMap { $0.value }
    }

    /// The file for this chapter. A file that names another chapter is never used.
    func file(forChapter chapter: Int) -> ChapterAudioFileDTO? {
        if let single = audioFile, single.chapterId == nil || single.chapterId == chapter {
            return single
        }
        if let match = audioFiles.first(where: { $0.chapterId == chapter }) {
            return match
        }
        if audioFiles.count == 1, let only = audioFiles.first, only.chapterId == nil {
            return only
        }
        return nil
    }
}

/// Documented fields: id, chapter_id, file_size, format, audio_url, duration (milliseconds, may be null),
/// timestamps (read later by the Timing builder, not here).
struct ChapterAudioFileDTO: Decodable, Sendable {
    let chapterId: Int?
    let audioUrl: String?
    let durationMilliseconds: Double?

    private enum CodingKeys: String, CodingKey {
        case chapterId
        case audioUrl
        case url
        case duration
    }

    init(chapterId: Int?, audioUrl: String?, durationMilliseconds: Double?) {
        self.chapterId = chapterId
        self.audioUrl = audioUrl
        self.durationMilliseconds = durationMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapterId = container.listenFlexibleInt(forKey: .chapterId)
        let primary = try? container.decodeIfPresent(String.self, forKey: .audioUrl)
        let fallback = try? container.decodeIfPresent(String.self, forKey: .url)
        audioUrl = primary ?? fallback
        durationMilliseconds = container.listenFlexibleDouble(forKey: .duration)
    }

    /// Seconds, or nil when the API gives no positive duration.
    var durationSeconds: Double? {
        guard let ms = durationMilliseconds, ms.isFinite, ms > 0 else { return nil }
        return ms / 1000
    }
}

// MARK: - Audio URLs

/// Turns the `audio_url` the API returns into a URL the player can stream.
enum ChapterAudioURL {
    /// Host for relative chapter audio paths. The documented example answer uses a full URL on this host
    /// (`https://download.quranicaudio.com/qdc/...`). The docs do not say chapter paths can be relative.
    static let relativeBaseString = "https://download.quranicaudio.com/"

    /// Full https URLs are kept, `http://` and `//host` become https (App Transport Security),
    /// relative paths are resolved against `relativeBaseString`. Anything else is refused.
    static func resolve(_ raw: String?) -> URL? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("//") {
            text = "https:" + text
        } else if text.lowercased().hasPrefix("http://") {
            text = "https://" + String(text.dropFirst("http://".count))
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
        // Any other scheme (file:, data:, javascript: ...) is refused.
        if text.contains("://") || URL(string: text)?.scheme != nil || text.contains("..") || text.contains("\\") {
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

// MARK: - Helpers

enum ListenCatalogText {
    /// Trimmed text, or nil when empty.
    static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Unicode blocks of the Arabic script, as code point ranges (no Arabic literals in code).
    private static let arabicScriptRanges: [ClosedRange<UInt32>] = [
        0x0600...0x06FF,
        0x0750...0x077F,
        0x0870...0x08FF,
        0xFB50...0xFDFF,
        0xFE70...0xFEFF,
    ]

    static func containsArabicScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            arabicScriptRanges.contains { $0.contains(scalar.value) }
        }
    }
}

private extension KeyedDecodingContainer {
    /// An integer given as a JSON number or a numeric string.
    func listenFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key),
           number.isFinite, number == number.rounded(), abs(number) < 1_000_000_000_000 {
            return Int(number)
        }
        return nil
    }

    /// A number given as a JSON number or a numeric string.
    func listenFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
