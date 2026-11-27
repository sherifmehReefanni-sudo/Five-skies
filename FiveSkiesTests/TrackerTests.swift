import XCTest
@testable import FiveSkies

final class TrackerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "TrackerTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Helpers

    private func utc() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func makeCalculator() throws -> StreakCalculator {
        StreakCalculator(timeZone: try utc())
    }

    /// 26 Nov 2026, 21:00 UTC.
    private func makeToday(_ calculator: StreakCalculator) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 26
        components.hour = 21
        return try XCTUnwrap(calculator.calendar.date(from: components))
    }

    private func date(_ calculator: StreakCalculator, _ today: Date, daysAgo: Int) throws -> Date {
        try XCTUnwrap(calculator.calendar.date(byAdding: .day, value: -daysAgo, to: today))
    }

    private func key(_ calculator: StreakCalculator, _ today: Date, daysAgo: Int) throws -> String {
        calculator.dayKey(for: try date(calculator, today, daysAgo: daysAgo))
    }

    private func keys(_ calculator: StreakCalculator, _ today: Date, daysAgo: [Int]) throws -> Set<String> {
        var result: Set<String> = []
        for offset in daysAgo {
            result.insert(try key(calculator, today, daysAgo: offset))
        }
        return result
    }

    private var allFive: Set<Prayer> { Set(Prayer.allCases) }

    private let usLocale = Locale(identifier: "en_US")

    // MARK: - Pauses

    func testPauseCoversItsDaysInclusively() {
        let pause = TrackerPause(reason: .travel, startKey: "2026-11-20", endKey: "2026-11-22")
        XCTAssertFalse(pause.covers("2026-11-19"))
        XCTAssertTrue(pause.covers("2026-11-20"))
        XCTAssertTrue(pause.covers("2026-11-21"))
        XCTAssertTrue(pause.covers("2026-11-22"))
        XCTAssertFalse(pause.covers("2026-11-23"))

        let openEnded = TrackerPause(reason: .illness, startKey: "2026-11-20")
        XCTAssertTrue(openEnded.covers("2027-03-01"))
        XCTAssertFalse(openEnded.covers("2026-10-31"))
    }

    func testPauseStoreRoundTripsEndsAndRemoves() {
        let store = PauseStore(defaults: defaults)
        XCTAssertEqual(store.all(), [])

        let recent = TrackerPause(reason: .monthlyBreak, startKey: "2026-11-20")
        let older = TrackerPause(reason: .travel, startKey: "2026-10-01", endKey: "2026-10-05")
        store.save(older)
        store.save(recent)
        XCTAssertEqual(PauseStore(defaults: defaults).all(), [recent, older], "newest start first")

        store.end(recent, lastPausedKey: "2026-11-25")
        XCTAssertEqual(store.all().first?.endKey, "2026-11-25")
        XCTAssertEqual(store.all().count, 2)

        store.end(older, lastPausedKey: "2026-09-30")
        XCTAssertEqual(store.all().map(\.id), [recent.id], "a pause ended before its first day is removed")

        store.remove(id: recent.id)
        XCTAssertEqual(store.all(), [])
        XCTAssertNil(defaults.data(forKey: PauseStore.storageKey))
    }

    // MARK: - Streak bridging

    func testPausedDaysBridgeTheCurrentStreak() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [1, 4, 5])
        let paused = try keys(calculator, today, daysAgo: [2, 3])

        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today, isPaused: { paused.contains($0) }), 3)
        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today), 1, "without the pause the gap breaks it")
    }

    func testPausedDaysNeitherAddNorBreakTheBestStreak() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [20, 19, 18, 15, 14, 2])
        let paused = try keys(calculator, today, daysAgo: [17, 16])

        XCTAssertEqual(calculator.bestStreak(completedDays: complete, isPaused: { paused.contains($0) }), 5)
        XCTAssertEqual(calculator.bestStreak(completedDays: complete), 3)
    }

    func testAnUnpausedGapStillBreaksTheStreak() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [0, 1, 3, 4])
        let paused = try keys(calculator, today, daysAgo: [5, 6])

        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today, isPaused: { paused.contains($0) }), 2)
        XCTAssertEqual(calculator.bestStreak(completedDays: complete, isPaused: { paused.contains($0) }), 2)
    }

    func testPausedTodayAndYesterdayKeepTheStreak() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [2, 3])
        let paused = try keys(calculator, today, daysAgo: [0, 1])

        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today, isPaused: { paused.contains($0) }), 2)
        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today), 0)
    }

    func testCompleteDayInsideAPauseStillCounts() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [0, 2, 3])
        let paused = try keys(calculator, today, daysAgo: [1, 2])

        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today, isPaused: { paused.contains($0) }), 3)
    }

    func testOpenEndedPauseBeforeTheFirstCompleteDayAddsNothing() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [0])

        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today, isPaused: { _ in true }), 1)
        XCTAssertEqual(calculator.bestStreak(completedDays: complete, isPaused: { _ in true }), 1)
        XCTAssertEqual(calculator.currentStreak(completedDays: [], today: today, isPaused: { _ in true }), 0)
    }

    func testPauseAwareStreaksMatchTheOldOnesWithoutPauses() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let complete = try keys(calculator, today, daysAgo: [0, 1, 5, 6, 7, 8, 20, 40, 41, 42])
        XCTAssertEqual(calculator.currentStreak(completedDays: complete, today: today), 2)
        XCTAssertEqual(calculator.bestStreak(completedDays: complete), 4)
    }

    // MARK: - History

    func testCountingStartsOnTheFirstTrackedDay() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let firstKey = try key(calculator, today, daysAgo: 3)
        let yesterdayKey = try key(calculator, today, daysAgo: 1)
        let days: [String: Set<Prayer>] = [firstKey: [.fajr], yesterdayKey: allFive]
        let history = TrackerHistory(days: days, pauses: [], calculator: calculator, locale: usLocale)

        XCTAssertEqual(history.firstTrackedKey, firstKey)
        XCTAssertEqual(history.status(for: try date(calculator, today, daysAgo: 5), today: today).phase, .notStarted)
        XCTAssertEqual(history.status(for: try date(calculator, today, daysAgo: 4), today: today).phase, .notStarted)
        let unmarked = history.status(for: try date(calculator, today, daysAgo: 2), today: today)
        XCTAssertEqual(unmarked.phase, .active)
        XCTAssertEqual(unmarked.count, 0)
        XCTAssertEqual(history.status(for: today, today: today).phase, .active)
        XCTAssertEqual(history.status(for: try date(calculator, today, daysAgo: -1), today: today).phase, .future)
        XCTAssertTrue(history.status(for: try date(calculator, today, daysAgo: 1), today: today).isComplete)
    }

    func testBeforeAnyTrackingOnlyTodayIsActive() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let history = TrackerHistory(days: [:], pauses: [], calculator: calculator, locale: usLocale)

        XCTAssertNil(history.firstTrackedKey)
        XCTAssertFalse(history.hasTracked)
        XCTAssertEqual(history.status(for: today, today: today).phase, .active)
        XCTAssertEqual(history.status(for: try date(calculator, today, daysAgo: 1), today: today).phase, .notStarted)
        XCTAssertEqual(history.monthStarts(today: today).count, 1)
        XCTAssertEqual(history.currentStreak(today: today), 0)
        XCTAssertEqual(history.bestStreak(), 0)
    }

    func testPausesBeforeTheFirstTrackedDayAreNotDrawn() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let firstKey = try key(calculator, today, daysAgo: 2)
        let startKey = try key(calculator, today, daysAgo: 6)
        let endKey = try key(calculator, today, daysAgo: 1)
        let days: [String: Set<Prayer>] = [firstKey: [.asr]]
        let pause = TrackerPause(reason: .travel, startKey: startKey, endKey: endKey)
        let history = TrackerHistory(days: days, pauses: [pause], calculator: calculator, locale: usLocale)

        let before = history.status(for: try date(calculator, today, daysAgo: 4), today: today)
        XCTAssertEqual(before.phase, .notStarted)
        XCTAssertFalse(before.isPaused)
        XCTAssertTrue(history.status(for: try date(calculator, today, daysAgo: 1), today: today).isPaused)
        XCTAssertFalse(history.status(for: today, today: today).isPaused)
    }

    func testTrendCoversSevenDaysEndingToday() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let history = TrackerHistory(days: [:], pauses: [], calculator: calculator, locale: usLocale)
        let dates = history.lastDays(7, endingOn: today)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.last.map(calculator.dayKey(for:)), calculator.dayKey(for: today))
        XCTAssertEqual(dates.first.map(calculator.dayKey(for:)), try key(calculator, today, daysAgo: 6))
    }

    func testWeekHasSevenConsecutiveDaysContainingToday() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let history = TrackerHistory(days: [:], pauses: [], calculator: calculator, locale: usLocale)
        let week = history.week(containing: today)

        XCTAssertEqual(week.count, 7)
        XCTAssertTrue(week.map(calculator.dayKey(for:)).contains(calculator.dayKey(for: today)))
        XCTAssertEqual(Set(week.map(calculator.dayKey(for:))).count, 7)
    }

    func testPerPrayerTotalsAndFullDays() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let yesterdayKey = try key(calculator, today, daysAgo: 1)
        let todayKey = try key(calculator, today, daysAgo: 0)
        let days: [String: Set<Prayer>] = [yesterdayKey: allFive, todayKey: [.fajr, .isha]]
        let history = TrackerHistory(days: days, pauses: [], calculator: calculator, locale: usLocale)
        let totals = history.perPrayerTotals()

        XCTAssertEqual(totals[.fajr], 2)
        XCTAssertEqual(totals[.dhuhr], 1)
        XCTAssertEqual(totals[.asr], 1)
        XCTAssertEqual(totals[.maghrib], 1)
        XCTAssertEqual(totals[.isha], 2)
        XCTAssertEqual(history.fullDayCount, 1)
        XCTAssertEqual(history.markedPrayerCount, 7)
    }

    func testLoadedHistoryBridgesStoredPausesAndFeedsTheChips() throws {
        let zone = try utc()
        let calculator = StreakCalculator(timeZone: zone)
        let today = try makeToday(calculator)
        let prayed = PrayedStore(defaults: defaults, timeZone: zone)
        for daysAgo in [1, 4, 5] {
            for prayer in Prayer.allCases {
                prayed.setPrayed(true, prayer, on: try date(calculator, today, daysAgo: daysAgo))
            }
        }
        prayed.setPrayed(true, .fajr, on: today)
        prayed.setPrayed(true, .dhuhr, on: today)
        let pauseStart = try key(calculator, today, daysAgo: 3)
        let pauseEnd = try key(calculator, today, daysAgo: 2)
        PauseStore(defaults: defaults).save(TrackerPause(reason: .illness, startKey: pauseStart, endKey: pauseEnd))

        let history = TrackerHistory.load(defaults: defaults, calculator: calculator, locale: usLocale)
        XCTAssertEqual(history.currentStreak(today: today), 3)
        XCTAssertEqual(history.bestStreak(), 3)
        XCTAssertEqual(history.chipsSummary(today: today), TrackerChipsSummary(markedToday: 2, streak: 3, isPausedToday: false))

        PauseStore(defaults: defaults).save(TrackerPause(reason: .travel, startKey: calculator.dayKey(for: today)))
        let paused = TrackerHistory.load(defaults: defaults, calculator: calculator, locale: usLocale)
        XCTAssertTrue(paused.chipsSummary(today: today).isPausedToday)
        XCTAssertEqual(paused.chipsSummary(today: today).streak, 3)
    }

    func testMonthGridLeadingBlanksFollowTheFirstWeekday() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let history = TrackerHistory(days: [:], pauses: [], calculator: calculator, locale: usLocale)
        let calendar = history.displayCalendar

        let november = history.month(startingAt: history.monthStart(containing: today))
        XCTAssertEqual(november.dates.count, 30)
        XCTAssertEqual(calculator.dayKey(for: november.start), "2026-11-01")
        // 1 Nov 2026 is a Sunday (weekday 1).
        XCTAssertEqual(november.leadingBlanks, (1 - calendar.firstWeekday + 7) % 7)

        let decemberStart = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: november.start))
        let december = history.month(startingAt: decemberStart)
        XCTAssertEqual(december.dates.count, 31)
        // 1 Dec 2026 is a Tuesday (weekday 3).
        XCTAssertEqual(december.leadingBlanks, (3 - calendar.firstWeekday + 7) % 7)
        XCTAssertEqual(history.weekdaySymbols.count, 7)
    }

    func testMonthStartsRunFromTheFirstTrackedMonth() throws {
        let calculator = try makeCalculator()
        let today = try makeToday(calculator)
        let history = TrackerHistory(days: ["2026-09-15": [.maghrib]], pauses: [], calculator: calculator, locale: usLocale)
        let starts = history.monthStarts(today: today)

        XCTAssertEqual(starts.map(calculator.dayKey(for:)), ["2026-09-01", "2026-10-01", "2026-11-01"])
    }

    // MARK: - Stores

    func testPrayedStoreReportsTheFirstTrackedDay() throws {
        let zone = try utc()
        let store = PrayedStore(defaults: defaults, timeZone: zone)
        XCTAssertNil(PrayedStore.firstTrackedDayKey(in: defaults))

        let later = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = later.addingTimeInterval(-3 * 24 * 3600)
        store.setPrayed(true, .asr, on: later)
        store.setPrayed(true, .fajr, on: earlier)
        XCTAssertEqual(PrayedStore.firstTrackedDayKey(in: defaults), store.dayKey(for: earlier))
        XCTAssertEqual(store.allDays().count, 2)

        store.setPrayed(false, .fajr, on: earlier)
        XCTAssertEqual(PrayedStore.firstTrackedDayKey(in: defaults), store.dayKey(for: later))
    }

    func testFastingLogFindsAnyLoggedFast() {
        let store = FastingLogStore(defaults: defaults)
        let voluntary = HijriDay(year: 1448, month: 5, day: 10)
        XCTAssertFalse(store.hasFastLogged(on: voluntary))

        store.setVoluntaryFast(true, on: voluntary)
        store.setFasted(true, day: 3, year: 1448)

        XCTAssertTrue(store.hasFastLogged(on: voluntary))
        XCTAssertTrue(store.hasFastLogged(on: HijriDay(year: 1448, month: 9, day: 3)))
        XCTAssertFalse(store.hasFastLogged(on: HijriDay(year: 1448, month: 9, day: 4)))
        XCTAssertFalse(store.hasFastLogged(on: HijriDay(year: 1447, month: 9, day: 3)))
        XCTAssertEqual(store.voluntaryFastCount, 1)
    }
}
