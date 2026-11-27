import Foundation

/// How one ayah can be highlighted while it plays (plan rule W3).
enum AyahWordAlignment: Equatable, Sendable {
    /// Quran Foundation word n is our word range at index n - 1.
    case words([Range<String.Index>])
    /// Highlight the whole ayah only.
    case ayahOnly

    var isWordLevel: Bool {
        if case .words = self { return true }
        return false
    }
}

/// Why an ayah fell back to ayah level. Numbers and names only, safe to log.
enum TimingFallbackReason: String, CaseIterable, Sendable {
    /// The timings have no entry for this ayah.
    case noTiming
    /// The entry has no usable word segments.
    case noWordTimings
    /// Quran Foundation's word count differs from ours.
    case countMismatch
    /// The counts match but their word numbers are not exactly 1 to n.
    case positionGap
}

/// Compares Quran Foundation's words with ours, one ayah at a time. Never guesses a mapping.
enum TimingAlignment {
    /// The distinct word numbers in an ayah's timings (each 1 or more). A word heard twice counts once.
    static func positions(in timing: AyahTiming) -> Set<Int> {
        Set(timing.words.map(\.position).filter { $0 >= 1 })
    }

    /// Word level when their distinct word numbers are exactly 1 to our word count; ayah level otherwise,
    /// with the reason.
    static func evaluate(_ text: FollowAlongText, timing: AyahTiming?) -> (alignment: AyahWordAlignment, fallback: TimingFallbackReason?) {
        guard let timing else { return (alignment: .ayahOnly, fallback: .noTiming) }
        let theirs = positions(in: timing)
        guard !theirs.isEmpty, text.wordCount > 0 else { return (alignment: .ayahOnly, fallback: .noWordTimings) }
        guard theirs.count == text.wordCount else { return (alignment: .ayahOnly, fallback: .countMismatch) }
        guard theirs == Set(1...text.wordCount) else { return (alignment: .ayahOnly, fallback: .positionGap) }
        return (alignment: .words(text.wordRanges), fallback: nil)
    }

    static func align(_ text: FollowAlongText, timing: AyahTiming?) -> AyahWordAlignment {
        evaluate(text, timing: timing).alignment
    }
}

/// Follow along for one surah: the reader's text for each ayah and how it lines up with the timings.
/// Build it once when the timings arrive (cheap: a few hundred ayahs at most), not on every word.
struct SurahFollowAlong: Sendable {
    let chapter: Int
    /// Nil when built without timings.
    let reciterID: Int?
    private let texts: [Int: FollowAlongText]
    private let alignments: [Int: AyahWordAlignment]
    private let fallbacks: [Int: TimingFallbackReason]

    /// `ayahs` are the stored ayahs of `chapter` (`QuranData.ayahs(inSura:)`), and `timings` the
    /// player's (`ListenPlayer.timings`). Timings for another chapter are ignored, as are ayahs of other suras.
    init(chapter: Int, ayahs: [Ayah], timings: SurahTimings?) {
        self.chapter = chapter
        let usable = timings?.chapter == chapter ? timings : nil
        reciterID = usable?.reciterID
        var byAyah: [Int: AyahTiming] = [:]
        for timing in usable?.ayahs ?? [] where byAyah[timing.ayah] == nil {
            byAyah[timing.ayah] = timing
        }
        var texts: [Int: FollowAlongText] = [:]
        var alignments: [Int: AyahWordAlignment] = [:]
        var fallbacks: [Int: TimingFallbackReason] = [:]
        for ayah in ayahs where ayah.sura == chapter && texts[ayah.number] == nil {
            let text = FollowAlongText(ayah: ayah)
            let result = TimingAlignment.evaluate(text, timing: byAyah[ayah.number])
            texts[ayah.number] = text
            alignments[ayah.number] = result.alignment
            if let reason = result.fallback {
                fallbacks[ayah.number] = reason
            }
        }
        self.texts = texts
        self.alignments = alignments
        self.fallbacks = fallbacks
    }

    /// The text the reader should draw for this ayah, with its word ranges.
    func text(forAyah ayah: Int) -> FollowAlongText? {
        texts[ayah]
    }

    func alignment(forAyah ayah: Int) -> AyahWordAlignment {
        alignments[ayah] ?? .ayahOnly
    }

    func fallbackReason(forAyah ayah: Int) -> TimingFallbackReason? {
        fallbacks[ayah]
    }

    /// The number of stored ayahs checked.
    var ayahsChecked: Int { texts.count }

    /// The number of those that highlight at ayah level only.
    var ayahsFallingBack: Int { fallbacks.count }

    /// Ayah numbers that fell back, in order, with the reason.
    var fallbackAyahs: [(ayah: Int, reason: TimingFallbackReason)] {
        fallbacks.keys.sorted().compactMap { key in
            fallbacks[key].map { (ayah: key, reason: $0) }
        }
    }
}

/// What the reader highlights right now.
enum FollowAlongHighlight: Equatable, Sendable {
    /// This ayah is playing and lines up at ayah level only: highlight the whole ayah.
    case wholeAyah(ayah: Int)
    /// This word is playing: highlight `range` within `SurahFollowAlong.text(forAyah:)!.text`.
    case word(ayah: Int, range: Range<String.Index>)
    /// This ayah lines up word by word, but no word is playing at this moment (a pause, or the
    /// basmala before ayah 1's first word). Mark the ayah as current; highlight no word.
    case betweenWords(ayah: Int)

    var ayah: Int {
        switch self {
        case .wholeAyah(let ayah), .betweenWords(let ayah):
            return ayah
        case .word(let ayah, _):
            return ayah
        }
    }
}

/// Turns the player's ayah and word into what the reader highlights. Pure, cheap enough for every update.
enum FollowAlongState {
    /// - Parameters:
    ///   - readerChapter: the surah on screen.
    ///   - playingChapter: `listenPlayer.item?.chapter`.
    ///   - currentAyah: `listenPlayer.currentAyah`.
    ///   - currentWord: `listenPlayer.currentWord` (Quran Foundation's word number).
    ///   - followAlong: built from `listenPlayer.timings` for `readerChapter`.
    /// - Returns: nil when nothing on this screen should be highlighted.
    static func highlight(
        readerChapter: Int,
        playingChapter: Int?,
        currentAyah: Int?,
        currentWord: Int?,
        followAlong: SurahFollowAlong?
    ) -> FollowAlongHighlight? {
        guard let playingChapter, playingChapter == readerChapter, let ayah = currentAyah else {
            return nil
        }
        guard let followAlong, followAlong.chapter == readerChapter, followAlong.text(forAyah: ayah) != nil else {
            return .wholeAyah(ayah: ayah)
        }
        switch followAlong.alignment(forAyah: ayah) {
        case .ayahOnly:
            return .wholeAyah(ayah: ayah)
        case .words(let ranges):
            guard let word = currentWord, word >= 1, word <= ranges.count else {
                return .betweenWords(ayah: ayah)
            }
            return .word(ayah: ayah, range: ranges[word - 1])
        }
    }
}
