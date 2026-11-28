import Foundation

// Shared contracts for the Listen tab (Phase B, round B1). Owned by the lead.
// Builders: Audio/ uses these types, Catalog/ produces them, UI/ shows them.
// No reciter names are typed in code: they come from the Quran Foundation API at run time.

/// A reciter as the Quran Foundation API lists it.
struct Reciter: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    /// The name exactly as the API gives it, shown with every recitation (D9).
    let name: String
    /// For example "Murattal", when the API gives one.
    let style: String?
}

/// Where one surah's full recitation can be streamed from.
struct ChapterAudio: Equatable, Sendable {
    let reciterID: Int
    let chapter: Int
    /// The file on the Quran Foundation hosts. Played straight from there, never through the relay (D3).
    let url: URL
    let durationSeconds: Double?
}

/// What the player is playing, with the credit line every player shows (D9).
struct NowPlayingItem: Equatable, Sendable {
    let reciter: Reciter
    let chapter: Int
    /// The surah name in English letters, from the bundled metadata.
    let chapterName: String
    let audio: ChapterAudio

    var credit: String {
        "\(reciter.name) \u{00B7} Quran Foundation"
    }
}

/// Where the player is.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}

/// Looks up reciters and surah audio. `RelayListenCatalog` (Catalog/) is the real one;
/// `FakeListenCatalog` (Catalog/) serves fixed test data and is used with `-FSFakeListen`.
protocol ListenCatalog: Sendable {
    func reciters() async throws -> [Reciter]
    func chapterAudio(reciterID: Int, chapter: Int) async throws -> ChapterAudio
}

/// The `-FSFakeListen` testing hook: fake catalog and a simulated player, no network, no audio.
enum ListenLaunch {
    static let fakeArgument = "-FSFakeListen"

    static func usesFakes(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(fakeArgument)
    }
}

// MARK: - Round C1 contracts (docs/LEARN_LISTEN_PLAN.md sections 2 and 3). Owned by the lead.

/// One word's place in a recitation, by Quran Foundation's word number in that ayah (1 based).
struct WordTiming: Equatable, Sendable {
    let position: Int
    let start: Double
    let end: Double
}

/// One ayah's place in a surah recitation, in seconds from the start of the file.
struct AyahTiming: Equatable, Sendable {
    let ayah: Int
    let start: Double
    let end: Double
    /// Empty when the source gives no word timings for this ayah.
    let words: [WordTiming]
}

/// Timings for one reciter's recitation of one surah, held in memory only.
struct SurahTimings: Equatable, Sendable {
    let reciterID: Int
    let chapter: Int
    let ayahs: [AyahTiming]

    /// The ayah playing at `seconds`, if any.
    func ayah(at seconds: Double) -> AyahTiming? {
        ayahs.first { seconds >= $0.start && seconds < $0.end }
    }
}

/// Supplies timings when they exist. Built by FiveSkies/Listen/Timing/.
protocol SurahTimingProviding: Sendable {
    func timings(reciterID: Int, chapter: Int) async -> SurahTimings?
}

/// What happens when a surah finishes (plan section 3).
enum SurahEndAction: Equatable, Codable, Sendable {
    case stop
    case playNext
    /// nil repeats until stopped.
    case repeatSurah(times: Int?)
    /// Plays surahs from `first` to `last`, then stops.
    case playSet(first: Int, last: Int)
}

/// The listener's play choices, remembered between launches.
struct PlayModes: Equatable, Codable, Sendable {
    static let ayahRepeatChoices = [1, 2, 3, 5, 10]
    static let surahRepeatChoices: [Int?] = [1, 3, 7, nil]

    var surahEnd: SurahEndAction = .stop
    /// Each ayah plays this many times before moving on. Needs timings; 1 means off.
    var ayahRepeat: Int = 1
    /// After each ayah, wait as long as the ayah lasted. Needs timings.
    var reciteAfterMe = false
    /// Pause when a prayer time arrives and offer to resume. On by default.
    var pausesForPrayer = true
    /// After each ayah, an English voice reads the user's chosen translation, then the
    /// recitation goes on. Needs timings. English text only; never a computer voice for Arabic.
    var readsMeaning = false
    /// Memorize: while the listener's turn waits (`reciteAfterMe`), the reader hides that ayah's
    /// Arabic until they tap to peek. The stored text and its drawing are never changed.
    var hidesAyahWhileWaiting = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case surahEnd, ayahRepeat, reciteAfterMe, pausesForPrayer, readsMeaning, hidesAyahWhileWaiting
    }

    /// Fields missing from an older saved copy keep their defaults, so adding a field never resets the rest.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        surahEnd = (try? container.decodeIfPresent(SurahEndAction.self, forKey: .surahEnd)) ?? .stop
        ayahRepeat = (try? container.decodeIfPresent(Int.self, forKey: .ayahRepeat)) ?? 1
        reciteAfterMe = (try? container.decodeIfPresent(Bool.self, forKey: .reciteAfterMe)) ?? false
        pausesForPrayer = (try? container.decodeIfPresent(Bool.self, forKey: .pausesForPrayer)) ?? true
        readsMeaning = (try? container.decodeIfPresent(Bool.self, forKey: .readsMeaning)) ?? false
        hidesAyahWhileWaiting = (try? container.decodeIfPresent(Bool.self, forKey: .hidesAyahWhileWaiting)) ?? false
    }
}

/// Makes the item for another surah with the same reciter, so the player can move on by itself.
/// Built by FiveSkies/Listen/UI/ from the catalog and the bundled surah names.
protocol ListenQueueResolving: Sendable {
    func item(chapter: Int, reciter: Reciter) async throws -> NowPlayingItem
}

/// The English meaning of one ayah, from the translation the user chose, with its source name.
struct AyahMeaning: Equatable, Sendable {
    let text: String
    /// For example the translator's name, shown while it is read.
    let source: String
}

/// Supplies the meaning to read after an ayah. The lead wires it from TranslationStore.
protocol AyahMeaningProviding: Sendable {
    func meaning(chapter: Int, ayah: Int) async -> AyahMeaning?
}
