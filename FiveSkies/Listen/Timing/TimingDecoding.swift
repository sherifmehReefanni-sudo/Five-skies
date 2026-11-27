import Foundation

// Tolerant decoder for GET /api/v4/chapter_recitations/{reciter_id}/{chapter}?segments=true.
// Documented answer (api-docs.quran.foundation, chapter-reciter-audio-file):
//   {"audio_file": {"chapter_id": 1, "timestamps": [
//      {"verse_key": "1:1", "timestamp_from": 0, "timestamp_to": 6493, "duration": -6493,
//       "segments": [[1, 0, 630], [2, 650, 1570], ...]}, ...]}}
// All times are milliseconds from the start of the file. Each segment is [word_index, start_ms, end_ms].
// The relay decoder converts snake case keys, so `timestamp_from` arrives as `timestampFrom`.
// Every field is optional, unknown fields are ignored and a bad entry is dropped, never fatal.
// Nothing decoded here is written to disk: timings are held in memory only.

/// Decodes a value, or holds nil when that one value is malformed.
struct TimingLossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// `{"audio_file": {...}}`. Also reads `{"audio_files": [...]}` in case the list shape comes back.
struct ChapterTimingResponse: Decodable, Sendable {
    let audioFile: ChapterTimingFileDTO?
    let audioFiles: [ChapterTimingFileDTO]

    private enum CodingKeys: String, CodingKey {
        case audioFile
        case audioFiles
    }

    init(audioFile: ChapterTimingFileDTO?, audioFiles: [ChapterTimingFileDTO] = []) {
        self.audioFile = audioFile
        self.audioFiles = audioFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioFile = try? container.decodeIfPresent(ChapterTimingFileDTO.self, forKey: .audioFile)
        let items = try? container.decodeIfPresent([TimingLossy<ChapterTimingFileDTO>].self, forKey: .audioFiles)
        audioFiles = (items ?? []).compactMap { $0.value }
    }

    /// The file for this chapter. A file that names another chapter is never used.
    func file(forChapter chapter: Int) -> ChapterTimingFileDTO? {
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

    /// The usable timings in seconds, sorted by ayah number, or nil when none are usable.
    /// Entries for other chapters, bad verse keys, bad times and repeated ayahs are dropped.
    func surahTimings(reciterID: Int, chapter: Int) -> SurahTimings? {
        guard let file = file(forChapter: chapter) else { return nil }
        var seen = Set<Int>()
        var ayahs: [AyahTiming] = []
        for entry in file.timestamps {
            guard let timing = entry.ayahTiming(chapter: chapter), !seen.contains(timing.ayah) else { continue }
            seen.insert(timing.ayah)
            ayahs.append(timing)
        }
        guard !ayahs.isEmpty else { return nil }
        ayahs.sort { $0.ayah < $1.ayah }
        return SurahTimings(reciterID: reciterID, chapter: chapter, ayahs: ayahs)
    }

    /// The ayah number from a verse key "chapter:ayah", or nil when the key is malformed
    /// or names another chapter.
    static func ayahNumber(verseKey: String?, chapter: Int) -> Int? {
        guard let key = verseKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let keyChapter = Int(parts[0]),
              let ayah = Int(parts[1]),
              keyChapter == chapter,
              ayah >= 1,
              ayah <= TimingLimits.maxAyah
        else {
            return nil
        }
        return ayah
    }
}

enum TimingLimits {
    /// The longest surah has 286 ayahs; anything far beyond is not a real ayah number.
    static let maxAyah = 1_000
    /// The longest ayah has well under 200 words; anything far beyond is not a real word number.
    static let maxWordPosition = 1_000

    /// Milliseconds to seconds, or nil when the value is not a usable time.
    static func seconds(fromMilliseconds ms: Double?) -> Double? {
        guard let ms, ms.isFinite, ms >= 0 else { return nil }
        return ms / 1000
    }
}

/// Documented fields: id, chapter_id, file_size, format, audio_url, timestamps. Only chapter_id and timestamps are read.
struct ChapterTimingFileDTO: Decodable, Sendable {
    let chapterId: Int?
    let timestamps: [VerseTimestampDTO]

    private enum CodingKeys: String, CodingKey {
        case chapterId
        case timestamps
    }

    init(chapterId: Int?, timestamps: [VerseTimestampDTO]) {
        self.chapterId = chapterId
        self.timestamps = timestamps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chapterId = container.timingInt(forKey: .chapterId)
        let items = try? container.decodeIfPresent([TimingLossy<VerseTimestampDTO>].self, forKey: .timestamps)
        timestamps = (items ?? []).compactMap { $0.value }
    }
}

/// One entry of `timestamps`: verse_key, timestamp_from, timestamp_to, duration (ignored), segments.
struct VerseTimestampDTO: Decodable, Sendable {
    let verseKey: String?
    let timestampFrom: Double?
    let timestampTo: Double?
    let segments: [WordSegmentDTO]

    private enum CodingKeys: String, CodingKey {
        case verseKey
        case timestampFrom
        case timestampTo
        case segments
    }

    init(verseKey: String?, timestampFrom: Double?, timestampTo: Double?, segments: [WordSegmentDTO]) {
        self.verseKey = verseKey
        self.timestampFrom = timestampFrom
        self.timestampTo = timestampTo
        self.segments = segments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verseKey = try? container.decodeIfPresent(String.self, forKey: .verseKey)
        timestampFrom = container.timingDouble(forKey: .timestampFrom)
        timestampTo = container.timingDouble(forKey: .timestampTo)
        let items = try? container.decodeIfPresent([TimingLossy<WordSegmentDTO>].self, forKey: .segments)
        segments = (items ?? []).compactMap { $0.value }
    }

    /// The ayah in seconds, or nil when the key or the ayah times are not usable.
    /// Word segments that are not usable are dropped; the ayah stays with the rest.
    func ayahTiming(chapter: Int) -> AyahTiming? {
        guard let ayah = ChapterTimingResponse.ayahNumber(verseKey: verseKey, chapter: chapter),
              let start = TimingLimits.seconds(fromMilliseconds: timestampFrom),
              let end = TimingLimits.seconds(fromMilliseconds: timestampTo),
              end > start
        else {
            return nil
        }
        let words = segments
            .compactMap { $0.wordTiming() }
            .sorted { $0.start < $1.start }
        return AyahTiming(ayah: ayah, start: start, end: end, words: words)
    }
}

/// One segment: a JSON array of numbers (numeric strings are accepted). Only the documented
/// triplet [word_index, start_ms, end_ms] is used; any other length is dropped rather than guessed.
struct WordSegmentDTO: Decodable, Sendable {
    let numbers: [Double]

    init(numbers: [Double]) {
        self.numbers = numbers
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Double] = []
        while !container.isAtEnd {
            // A failed decode does not move the container on, so every branch either
            // consumes one element or throws.
            if let number = try? container.decode(Double.self) {
                values.append(number)
            } else if let text = try? container.decode(String.self),
                      let number = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                values.append(number)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Segment entry is not a number")
            }
        }
        numbers = values
    }

    /// The word in seconds, or nil unless this is a triplet with a whole word number of 1 or more,
    /// a start of 0 or more and an end after the start.
    func wordTiming() -> WordTiming? {
        guard numbers.count == 3 else { return nil }
        let rawPosition = numbers[0]
        guard rawPosition.isFinite,
              rawPosition == rawPosition.rounded(),
              rawPosition >= 1,
              rawPosition <= Double(TimingLimits.maxWordPosition),
              let start = TimingLimits.seconds(fromMilliseconds: numbers[1]),
              let end = TimingLimits.seconds(fromMilliseconds: numbers[2]),
              end > start
        else {
            return nil
        }
        return WordTiming(position: Int(rawPosition), start: start, end: end)
    }
}

private extension KeyedDecodingContainer {
    /// An integer given as a JSON number or a numeric string.
    func timingInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let number = try? decodeIfPresent(Double.self, forKey: key),
           number.isFinite, number == number.rounded(), abs(number) < 1_000_000_000 {
            return Int(number)
        }
        return nil
    }

    /// A number given as a JSON number or a numeric string.
    func timingDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
