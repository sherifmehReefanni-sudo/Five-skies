import Foundation

/// How well an ayah is known, as marked by the reader.
enum MemorizeStatus: String, Codable, Sendable {
    case known
    case learning
}

/// Splits the stored ayah text for the "First words" mode. Never changes the text itself.
enum MemorizeText {
    struct Split: Equatable {
        /// The stored text up to the end of the last shown word.
        let prefix: String
        /// Whether any words follow the prefix.
        let hasRemainder: Bool
    }

    /// The refs for an ayah range of one sura.
    static func refs(sura: Int, range: ClosedRange<Int>) -> [AyahRef] {
        range.map { AyahRef(sura: sura, aya: $0) }
    }

    /// The first `count` words, where words are separated by the ASCII space character.
    /// Works on Unicode scalars so the marks of the text are never touched.
    static func firstWords(_ text: String, count: Int = 2) -> Split {
        let scalars = text.unicodeScalars
        guard count > 0 else {
            return Split(prefix: "", hasRemainder: scalars.contains { $0 != " " })
        }
        var words = 0
        var inWord = false
        var index = scalars.startIndex
        while index < scalars.endIndex {
            if scalars[index] == " " {
                if inWord {
                    inWord = false
                    if words == count {
                        let prefix = String(scalars[scalars.startIndex..<index])
                        let rest = scalars[index...]
                        return Split(prefix: prefix, hasRemainder: rest.contains { $0 != " " })
                    }
                }
            } else if !inWord {
                inWord = true
                words += 1
            }
            index = scalars.index(after: index)
        }
        return Split(prefix: text, hasRemainder: false)
    }
}

/// When a known ayah comes back for review (docs/LEARN_LISTEN_PLAN.md L3). Pure.
/// Marking an ayah known brings it back the next day (stage 0). Each "I remembered it" moves one
/// stage on: 3, 7, 14, then 30 days, and every 30 days after that. "Needs practice" goes back to
/// stage 0, so the ayah comes back tomorrow. Dates are calendar days, so a clock change never
/// moves a review by an hour.
enum MemorizeReview {
    /// Days until the next review, by stage.
    static let intervals = [1, 3, 7, 14, 30]

    static var lastStage: Int { intervals.count - 1 }

    static func interval(forStage stage: Int) -> Int {
        intervals[min(max(stage, 0), lastStage)]
    }

    /// The first review of an ayah marked known on `date`.
    static func first(from date: Date, calendar: Calendar) -> (stage: Int, date: Date) {
        (stage: 0, date: day(interval(forStage: 0), after: date, calendar: calendar))
    }

    /// The review after one answered on `date` at `stage`.
    static func next(stage: Int, remembered: Bool, from date: Date, calendar: Calendar) -> (stage: Int, date: Date) {
        let newStage = remembered ? min(max(stage, 0) + 1, lastStage) : 0
        return (stage: newStage, date: day(interval(forStage: newStage), after: date, calendar: calendar))
    }

    /// The start of the calendar day `days` after the day of `date`.
    static func day(_ days: Int, after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
    }

    /// Due on or after the day of `nextReview`. No date (an ayah marked known before reviews
    /// existed) means due today.
    static func isDue(_ nextReview: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let nextReview else { return true }
        return calendar.startOfDay(for: nextReview) <= calendar.startOfDay(for: now)
    }
}

/// Per ayah memorisation marks and their review schedule: the one memorize store, used by the
/// reader's "I know this", the Memorize screen and Review. Stored in UserDefaults under
/// "memorizeProgress" (in the iCloud backup) as JSON of numbers, a status and dates only.
/// Entries written before reviews existed hold only sura, aya and status, and still load.
@MainActor
final class MemorizeProgressStore: ObservableObject {
    nonisolated static let storageKey = "memorizeProgress"
    /// The round E2 reader's own list of "sura:aya" strings. Carried over once, then removed.
    nonisolated static let legacyKnownKey = "memorize.knownAyahs"
    /// UI tests: two known ayahs (1:1 and 1:2) due for review, in a throwaway suite.
    nonisolated static let sampleArgument = "-FSReviewSample"
    nonisolated static let sampleSuiteName = "FiveSkies.reviewSample"

    static let shared = MemorizeProgressStore.makeShared()

    /// When a known ayah was marked and when it comes back.
    struct Schedule: Equatable, Sendable {
        var knownSince: Date?
        var reviewStage: Int?
        var nextReview: Date?
    }

    private struct Entry: Codable {
        let sura: Int
        let aya: Int
        let status: MemorizeStatus
        // Optional so older entries decode (synthesized decoding uses decodeIfPresent), and
        // left out of the JSON when nil.
        let knownSince: Date?
        let reviewStage: Int?
        let nextReview: Date?
    }

    @Published private(set) var statuses: [AyahRef: MemorizeStatus]
    @Published private(set) var schedules: [AyahRef: Schedule]

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = MemorizeProgressStore.storageKey,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.key = key
        let loaded = Self.read(from: defaults, key: key)
        statuses = loaded.statuses
        schedules = loaded.schedules
        migrateLegacyKnown(now: now, calendar: calendar)
    }

    // MARK: - Reading

    func status(for ref: AyahRef) -> MemorizeStatus? {
        statuses[ref]
    }

    func isKnown(_ ref: AyahRef) -> Bool {
        statuses[ref] == .known
    }

    func schedule(for ref: AyahRef) -> Schedule? {
        schedules[ref]
    }

    /// How many of `refs` are marked known.
    func knownCount(in refs: [AyahRef]) -> Int {
        refs.filter { statuses[$0] == .known }.count
    }

    /// Known ayahs due on the day of `now`, in Quran order.
    func dueForReview(now: Date, calendar: Calendar = .current) -> [AyahRef] {
        statuses
            .compactMap { element -> AyahRef? in
                guard element.value == .known,
                      MemorizeReview.isDue(schedules[element.key]?.nextReview, now: now, calendar: calendar)
                else { return nil }
                return element.key
            }
            .sorted()
    }

    // MARK: - Marking

    func mark(_ ref: AyahRef, as status: MemorizeStatus) {
        switch status {
        case .known:
            markKnown(ref)
        case .learning:
            guard statuses[ref] != .learning else { return }
            statuses[ref] = .learning
            schedules[ref] = nil
            save()
        }
    }

    /// Marks `ref` known and schedules its first review for the next day.
    /// An ayah already known keeps its schedule.
    func markKnown(_ ref: AyahRef, at date: Date = Date(), calendar: Calendar = .current) {
        guard statuses[ref] != .known else { return }
        statuses[ref] = .known
        schedules[ref] = Self.firstSchedule(at: date, calendar: calendar)
        save()
    }

    /// Removes the mark and its schedule.
    func clear(_ ref: AyahRef) {
        guard statuses[ref] != nil || schedules[ref] != nil else { return }
        statuses[ref] = nil
        schedules[ref] = nil
        save()
    }

    /// Records one review answer. The ayah stays known either way. Ignored for an ayah not known.
    func recordReview(_ ref: AyahRef, remembered: Bool, at date: Date = Date(), calendar: Calendar = .current) {
        guard statuses[ref] == .known else { return }
        let current = schedules[ref]
        let next = MemorizeReview.next(
            stage: current?.reviewStage ?? 0,
            remembered: remembered,
            from: date,
            calendar: calendar
        )
        schedules[ref] = Schedule(knownSince: current?.knownSince, reviewStage: next.stage, nextReview: next.date)
        save()
    }

    // MARK: - Legacy marks

    /// Reads one legacy "sura:aya" string. Nil for anything else.
    nonisolated static func legacyRef(from key: String) -> AyahRef? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let sura = Int(parts[0]), let aya = Int(parts[1]),
              (1...114).contains(sura), aya >= 1
        else { return nil }
        return AyahRef(sura: sura, aya: aya)
    }

    /// Valid legacy refs, without repeats, in Quran order.
    nonisolated static func legacyRefs(from keys: [String]) -> [AyahRef] {
        Array(Set(keys.compactMap { legacyRef(from: $0) })).sorted()
    }

    /// Carries the E2 reader's marks over as known, keeping every entry already here
    /// (a known ayah keeps its schedule; one marked learning becomes known), then removes the old key.
    private func migrateLegacyKnown(now: Date, calendar: Calendar) {
        guard let value = defaults.object(forKey: Self.legacyKnownKey) else { return }
        let keys = value as? [String] ?? []
        for ref in Self.legacyRefs(from: keys) where statuses[ref] != .known {
            statuses[ref] = .known
            schedules[ref] = Self.firstSchedule(at: now, calendar: calendar)
        }
        save()
        defaults.removeObject(forKey: Self.legacyKnownKey)
    }

    // MARK: - UI test sample

    private static func makeShared() -> MemorizeProgressStore {
        guard ProcessInfo.processInfo.arguments.contains(sampleArgument) else {
            return MemorizeProgressStore()
        }
        // Never the standard defaults: a suite that is emptied on every launch.
        // `UserDefaults(suiteName:)` is nil only for the app's bundle id or the global domain.
        let defaults = UserDefaults(suiteName: sampleSuiteName)!
        defaults.removePersistentDomain(forName: sampleSuiteName)
        return makeSample(defaults: defaults, now: Date(), calendar: .current)
    }

    /// 1:1 and 1:2 known, both due since three days ago.
    static func makeSample(defaults: UserDefaults, now: Date, calendar: Calendar) -> MemorizeProgressStore {
        let store = MemorizeProgressStore(defaults: defaults, now: now, calendar: calendar)
        let since = MemorizeReview.day(-10, after: now, calendar: calendar)
        let due = MemorizeReview.day(-3, after: now, calendar: calendar)
        for aya in 1...2 {
            let ref = AyahRef(sura: 1, aya: aya)
            store.statuses[ref] = .known
            store.schedules[ref] = Schedule(knownSince: since, reviewStage: 1, nextReview: due)
        }
        store.save()
        return store
    }

    // MARK: - Storage

    private static func firstSchedule(at date: Date, calendar: Calendar) -> Schedule {
        let first = MemorizeReview.first(from: date, calendar: calendar)
        return Schedule(knownSince: date, reviewStage: first.stage, nextReview: first.date)
    }

    private func save() {
        let entries = statuses
            .map { element -> Entry in
                let schedule = element.value == .known ? schedules[element.key] : nil
                return Entry(
                    sura: element.key.sura,
                    aya: element.key.aya,
                    status: element.value,
                    knownSince: schedule?.knownSince,
                    reviewStage: schedule?.reviewStage,
                    nextReview: schedule?.nextReview
                )
            }
            .sorted { AyahRef(sura: $0.sura, aya: $0.aya) < AyahRef(sura: $1.sura, aya: $1.aya) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func read(
        from defaults: UserDefaults,
        key: String
    ) -> (statuses: [AyahRef: MemorizeStatus], schedules: [AyahRef: Schedule]) {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return ([:], [:])
        }
        var statuses: [AyahRef: MemorizeStatus] = [:]
        var schedules: [AyahRef: Schedule] = [:]
        for entry in entries {
            let ref = AyahRef(sura: entry.sura, aya: entry.aya)
            statuses[ref] = entry.status
            if entry.status == .known,
               entry.knownSince != nil || entry.reviewStage != nil || entry.nextReview != nil {
                schedules[ref] = Schedule(
                    knownSince: entry.knownSince,
                    reviewStage: entry.reviewStage,
                    nextReview: entry.nextReview
                )
            }
        }
        return (statuses, schedules)
    }
}
