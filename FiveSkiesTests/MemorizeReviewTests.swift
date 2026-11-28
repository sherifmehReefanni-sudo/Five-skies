import XCTest
@testable import FiveSkies

/// L3 review: the schedule math, the one store's migration from the E2 reader key,
/// old JSON, due ordering and answers. Fixed time zones throughout.
final class MemorizeReviewTests: XCTestCase {
    // MARK: - Helpers

    private func newYork() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
        in calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func parts(_ date: Date, in calendar: Calendar) -> [Int] {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return [c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? -1, c.minute ?? -1]
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "MemorizeReviewTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    // MARK: - Schedule math

    func testIntervalsByStage() {
        XCTAssertEqual(MemorizeReview.intervals, [1, 3, 7, 14, 30])
        XCTAssertEqual((0...7).map { MemorizeReview.interval(forStage: $0) }, [1, 3, 7, 14, 30, 30, 30, 30])
        XCTAssertEqual(MemorizeReview.interval(forStage: -2), 1)
    }

    func testFirstReviewIsTheNextCalendarDay() throws {
        let calendar = try newYork()
        let first = MemorizeReview.first(from: try date(2026, 5, 10, 23, 50, in: calendar), calendar: calendar)
        XCTAssertEqual(first.stage, 0)
        XCTAssertEqual(parts(first.date, in: calendar), [2026, 5, 11, 0, 0])
    }

    func testRememberedAcrossTheSpringClockChange() throws {
        // New York moves its clocks forward on Sunday March 8, 2026.
        let calendar = try newYork()
        let from = try date(2026, 3, 7, 21, 30, in: calendar)
        let next = MemorizeReview.next(stage: 0, remembered: true, from: from, calendar: calendar)
        XCTAssertEqual(next.stage, 1)
        XCTAssertEqual(parts(next.date, in: calendar), [2026, 3, 10, 0, 0])
        let start = calendar.startOfDay(for: from)
        XCTAssertEqual(next.date.timeIntervalSince(start), 3 * 86_400 - 3_600, accuracy: 0.5)
    }

    func testRememberedAcrossTheAutumnClockChange() throws {
        // New York moves its clocks back on Sunday November 1, 2026.
        let calendar = try newYork()
        let from = try date(2026, 10, 31, 8, 0, in: calendar)
        let next = MemorizeReview.next(stage: 1, remembered: true, from: from, calendar: calendar)
        XCTAssertEqual(next.stage, 2)
        XCTAssertEqual(parts(next.date, in: calendar), [2026, 11, 7, 0, 0])
        let start = calendar.startOfDay(for: from)
        XCTAssertEqual(next.date.timeIntervalSince(start), 7 * 86_400 + 3_600, accuracy: 0.5)
    }

    func testRememberingEachTimeGivesOneThreeSevenFourteenThenThirty() throws {
        let calendar = try newYork()
        let marked = try date(2026, 1, 1, 9, 0, in: calendar)
        var schedule = MemorizeReview.first(from: marked, calendar: calendar)
        var previous = calendar.startOfDay(for: marked)
        var gaps: [Int] = []
        for _ in 0..<6 {
            let gap = calendar.dateComponents([.day], from: previous, to: schedule.date).day ?? -1
            gaps.append(gap)
            previous = schedule.date
            // Answered in the evening of the day it came back.
            let answeredAt = schedule.date.addingTimeInterval(20 * 3_600)
            schedule = MemorizeReview.next(stage: schedule.stage, remembered: true, from: answeredAt, calendar: calendar)
        }
        XCTAssertEqual(gaps, [1, 3, 7, 14, 30, 30])
    }

    func testNeedsPracticeGoesBackToTomorrow() throws {
        let calendar = try newYork()
        let from = try date(2026, 6, 1, 15, 0, in: calendar)
        let next = MemorizeReview.next(stage: 4, remembered: false, from: from, calendar: calendar)
        XCTAssertEqual(next.stage, 0)
        XCTAssertEqual(parts(next.date, in: calendar), [2026, 6, 2, 0, 0])
    }

    func testDueIsByCalendarDay() throws {
        let calendar = try newYork()
        let review = try date(2026, 6, 2, 0, 0, in: calendar)
        XCTAssertTrue(MemorizeReview.isDue(nil, now: try date(2026, 6, 1, in: calendar), calendar: calendar))
        XCTAssertFalse(MemorizeReview.isDue(review, now: try date(2026, 6, 1, 23, 59, in: calendar), calendar: calendar))
        XCTAssertTrue(MemorizeReview.isDue(review, now: try date(2026, 6, 2, 0, 1, in: calendar), calendar: calendar))
        XCTAssertTrue(MemorizeReview.isDue(review, now: try date(2026, 6, 9, in: calendar), calendar: calendar))
    }

    // MARK: - Legacy migration

    func testLegacyRefParsing() {
        XCTAssertEqual(MemorizeProgressStore.legacyRef(from: "2:255"), AyahRef(sura: 2, aya: 255))
        XCTAssertEqual(MemorizeProgressStore.legacyRef(from: "114:6"), AyahRef(sura: 114, aya: 6))
        for bad in ["", "junk", "0:3", "115:1", "1:0", "3:x", "4:2:1", ":5", "5:", "-1:2"] {
            XCTAssertNil(MemorizeProgressStore.legacyRef(from: bad), bad)
        }
        XCTAssertEqual(
            MemorizeProgressStore.legacyRefs(from: ["2:255", "1:1", "2:255", "x"]),
            [AyahRef(sura: 1, aya: 1), AyahRef(sura: 2, aya: 255)]
        )
    }

    @MainActor
    func testLegacyMarksMoveIntoTheOneStoreAndTheOldKeyGoes() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try newYork()
        let earlier = try date(2026, 9, 1, in: calendar)
        let now = try date(2026, 11, 28, 10, 0, in: calendar)

        // Marks already in the store before the E2 key is read.
        let before = MemorizeProgressStore(defaults: defaults, now: earlier, calendar: calendar)
        before.markKnown(AyahRef(sura: 3, aya: 4), at: earlier, calendar: calendar)
        before.mark(AyahRef(sura: 1, aya: 1), as: .learning)
        let keptSchedule = before.schedule(for: AyahRef(sura: 3, aya: 4))
        XCTAssertNotNil(keptSchedule)

        defaults.set(["1:1", "2:255", "2:255", "3:4", "junk", "0:3"], forKey: MemorizeProgressStore.legacyKnownKey)
        let store = MemorizeProgressStore(defaults: defaults, now: now, calendar: calendar)

        XCTAssertNil(defaults.object(forKey: MemorizeProgressStore.legacyKnownKey), "The old key should be removed")
        XCTAssertEqual(store.statuses.count, 3)
        XCTAssertTrue(store.isKnown(AyahRef(sura: 1, aya: 1)))
        XCTAssertTrue(store.isKnown(AyahRef(sura: 2, aya: 255)))
        XCTAssertTrue(store.isKnown(AyahRef(sura: 3, aya: 4)))
        XCTAssertEqual(store.schedule(for: AyahRef(sura: 3, aya: 4)), keptSchedule, "An existing known mark keeps its schedule")
        let moved = try XCTUnwrap(store.schedule(for: AyahRef(sura: 2, aya: 255)))
        XCTAssertEqual(moved.reviewStage, 0)
        XCTAssertEqual(moved.knownSince, now)
        XCTAssertEqual(parts(try XCTUnwrap(moved.nextReview), in: calendar), [2026, 11, 29, 0, 0])

        // Saved, so a later launch sees the same marks without the old key.
        let reloaded = MemorizeProgressStore(defaults: defaults, now: now, calendar: calendar)
        XCTAssertEqual(reloaded.statuses, store.statuses)
        XCTAssertEqual(reloaded.schedules, store.schedules)
    }

    @MainActor
    func testNoLegacyKeyChangesNothing() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizeProgressStore(defaults: defaults)
        XCTAssertTrue(store.statuses.isEmpty)
        XCTAssertNil(defaults.data(forKey: MemorizeProgressStore.storageKey))
    }

    @MainActor
    func testUnreadableLegacyValueIsRemoved() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(42, forKey: MemorizeProgressStore.legacyKnownKey)
        let store = MemorizeProgressStore(defaults: defaults)
        XCTAssertTrue(store.statuses.isEmpty)
        XCTAssertNil(defaults.object(forKey: MemorizeProgressStore.legacyKnownKey))
    }

    // MARK: - Old JSON

    @MainActor
    func testOldEntriesDecodeAndOldKnownIsDueToday() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let json = #"[{"sura":1,"aya":1,"status":"learning"},{"sura":2,"aya":255,"status":"known"}]"#
        defaults.set(Data(json.utf8), forKey: MemorizeProgressStore.storageKey)

        let store = MemorizeProgressStore(defaults: defaults)
        XCTAssertEqual(store.status(for: AyahRef(sura: 1, aya: 1)), .learning)
        XCTAssertEqual(store.status(for: AyahRef(sura: 2, aya: 255)), .known)
        XCTAssertNil(store.schedule(for: AyahRef(sura: 2, aya: 255)))
        XCTAssertEqual(store.dueForReview(now: Date()), [AyahRef(sura: 2, aya: 255)])

        // Reviewing it once gives it a schedule from then on.
        let calendar = try newYork()
        let now = try date(2026, 11, 28, in: calendar)
        store.recordReview(AyahRef(sura: 2, aya: 255), remembered: true, at: now, calendar: calendar)
        let schedule = try XCTUnwrap(store.schedule(for: AyahRef(sura: 2, aya: 255)))
        XCTAssertEqual(schedule.reviewStage, 1)
        XCTAssertNil(schedule.knownSince)
        XCTAssertEqual(parts(try XCTUnwrap(schedule.nextReview), in: calendar), [2026, 12, 1, 0, 0])
    }

    // MARK: - Due and answers

    @MainActor
    func testDueAyahsComeInQuranOrder() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try newYork()
        let marked = try date(2026, 4, 1, in: calendar)
        let store = MemorizeProgressStore(defaults: defaults, now: marked, calendar: calendar)
        for ref in [AyahRef(sura: 114, aya: 1), AyahRef(sura: 2, aya: 255), AyahRef(sura: 1, aya: 7), AyahRef(sura: 1, aya: 1)] {
            store.markKnown(ref, at: marked, calendar: calendar)
        }
        store.mark(AyahRef(sura: 1, aya: 2), as: .learning)

        XCTAssertEqual(store.dueForReview(now: marked, calendar: calendar), [])
        XCTAssertEqual(
            store.dueForReview(now: try date(2026, 4, 2, 7, 0, in: calendar), calendar: calendar),
            [AyahRef(sura: 1, aya: 1), AyahRef(sura: 1, aya: 7), AyahRef(sura: 2, aya: 255), AyahRef(sura: 114, aya: 1)]
        )
    }

    @MainActor
    func testRecordReviewBothWays() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try newYork()
        let ref = AyahRef(sura: 112, aya: 1)
        let marked = try date(2026, 4, 1, in: calendar)
        let store = MemorizeProgressStore(defaults: defaults, now: marked, calendar: calendar)
        store.markKnown(ref, at: marked, calendar: calendar)

        store.recordReview(ref, remembered: true, at: try date(2026, 4, 2, in: calendar), calendar: calendar)
        var schedule = try XCTUnwrap(store.schedule(for: ref))
        XCTAssertEqual(schedule.reviewStage, 1)
        XCTAssertEqual(schedule.knownSince, marked)
        XCTAssertEqual(parts(try XCTUnwrap(schedule.nextReview), in: calendar), [2026, 4, 5, 0, 0])
        XCTAssertEqual(store.dueForReview(now: try date(2026, 4, 4, in: calendar), calendar: calendar), [])
        XCTAssertEqual(store.dueForReview(now: try date(2026, 4, 5, in: calendar), calendar: calendar), [ref])

        store.recordReview(ref, remembered: false, at: try date(2026, 4, 5, in: calendar), calendar: calendar)
        schedule = try XCTUnwrap(store.schedule(for: ref))
        XCTAssertEqual(store.status(for: ref), .known, "Needs practice keeps the ayah known")
        XCTAssertEqual(schedule.reviewStage, 0)
        XCTAssertEqual(parts(try XCTUnwrap(schedule.nextReview), in: calendar), [2026, 4, 6, 0, 0])

        let reloaded = MemorizeProgressStore(defaults: defaults, now: marked, calendar: calendar)
        XCTAssertEqual(reloaded.schedule(for: ref), schedule)
    }

    @MainActor
    func testRecordReviewIgnoresAyahsNotKnown() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemorizeProgressStore(defaults: defaults)
        let ref = AyahRef(sura: 2, aya: 1)
        store.recordReview(ref, remembered: true)
        XCTAssertNil(store.status(for: ref))
        store.mark(ref, as: .learning)
        store.recordReview(ref, remembered: true)
        XCTAssertNil(store.schedule(for: ref))
    }

    @MainActor
    func testMarkingKnownAgainKeepsTheSchedule() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try newYork()
        let ref = AyahRef(sura: 2, aya: 255)
        let store = MemorizeProgressStore(defaults: defaults)
        store.markKnown(ref, at: try date(2026, 4, 1, in: calendar), calendar: calendar)
        let schedule = store.schedule(for: ref)
        store.markKnown(ref, at: try date(2026, 5, 1, in: calendar), calendar: calendar)
        store.mark(ref, as: .known)
        XCTAssertEqual(store.schedule(for: ref), schedule)
    }

    @MainActor
    func testClearAndLearningRemoveTheSchedule() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ref = AyahRef(sura: 2, aya: 255)
        let other = AyahRef(sura: 2, aya: 256)
        let store = MemorizeProgressStore(defaults: defaults)
        store.markKnown(ref)
        store.markKnown(other)
        XCTAssertNotNil(store.schedule(for: ref))

        store.clear(ref)
        store.mark(other, as: .learning)
        XCTAssertNil(store.status(for: ref))
        XCTAssertNil(store.schedule(for: ref))
        XCTAssertNil(store.schedule(for: other))

        let reloaded = MemorizeProgressStore(defaults: defaults)
        XCTAssertNil(reloaded.status(for: ref))
        XCTAssertNil(reloaded.schedule(for: ref))
        XCTAssertEqual(reloaded.status(for: other), .learning)
        XCTAssertNil(reloaded.schedule(for: other))
    }

    // MARK: - Sample and words

    @MainActor
    func testSampleHasTwoAyahsDue() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = try newYork()
        let now = try date(2026, 11, 28, 19, 0, in: calendar)
        let store = MemorizeProgressStore.makeSample(defaults: defaults, now: now, calendar: calendar)
        XCTAssertEqual(store.dueForReview(now: now, calendar: calendar), [AyahRef(sura: 1, aya: 1), AyahRef(sura: 1, aya: 2)])
        XCTAssertNotNil(defaults.data(forKey: MemorizeProgressStore.storageKey))
    }

    func testReviewWords() {
        XCTAssertEqual(LearnReviewText.summary(count: 0), "Nothing to review today")
        XCTAssertEqual(LearnReviewText.summary(count: 1), "1 ayah to review today")
        XCTAssertEqual(LearnReviewText.summary(count: 3), "3 ayahs to review today")
        XCTAssertEqual(LearnReviewText.reference(AyahRef(sura: 2, aya: 255), suraName: "Al-Baqara"), "Al-Baqara 2:255")
        XCTAssertEqual(LearnReviewText.reference(AyahRef(sura: 2, aya: 255), suraName: nil), "Surah 2:255")
        XCTAssertFalse(LearnReviewText.empty.contains("\u{2014}"))
    }
}
