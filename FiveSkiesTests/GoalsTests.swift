import XCTest
@testable import FiveSkies

final class GoalsTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    private func newYork() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "GoalsTests.\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private func date(
        _ counter: GoalCounter,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        _ second: Int = 0
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return try XCTUnwrap(counter.calendar.date(from: components))
    }

    // MARK: - Progress value

    func testProgressIsACountTowardATarget() {
        let partial = GoalProgress(count: 3, target: 9)
        XCTAssertEqual(partial.fraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(partial.isComplete)
        XCTAssertEqual(partial.text, "3 of 9")

        let over = GoalProgress(count: 12, target: 9)
        XCTAssertEqual(over.fraction, 1, accuracy: 0.0001)
        XCTAssertTrue(over.isComplete)

        let noTarget = GoalProgress(count: 5, target: 0)
        XCTAssertEqual(noTarget.fraction, 0)
        XCTAssertFalse(noTarget.isComplete)
        XCTAssertEqual(GoalProgress(count: -2, target: 5).count, 0)
    }

    func testTargetIsClampedToTheTemplateRange() {
        XCTAssertEqual(PersonalGoal(kind: .fajrThisMonth, target: 45, startKey: "2026-11-01").target, 31)
        XCTAssertEqual(PersonalGoal(kind: .allFiveDays, target: 0, startKey: "2026-11-01").target, 1)
        XCTAssertEqual(PersonalGoal(kind: .custom, name: "  ", target: 5, startKey: "2026-11-01").title, "My goal")
        XCTAssertEqual(PersonalGoal(kind: .allFiveDays, target: 40, startKey: "2026-11-01").title, "All five prayers on 40 days")
    }

    // MARK: - Month boundaries

    func testFajrThisMonthCountsOnlyTheCurrentLocalMonth() throws {
        let counter = GoalCounter(timeZone: try newYork())
        let goal = PersonalGoal(kind: .fajrThisMonth, target: 2, startKey: "2026-10-20")
        let days: [String: Set<Prayer>] = [
            "2026-10-31": [.fajr],
            "2026-11-01": [.fajr, .dhuhr],
            "2026-11-15": [.dhuhr, .asr],
            "2026-11-30": [.fajr],
            "2026-12-01": [.fajr]
        ]

        let lastEveningOfOctober = try date(counter, 2026, 10, 31, 23, 30)
        XCTAssertEqual(counter.count(for: goal, today: lastEveningOfOctober, prayedDays: days, dhikr: DhikrTotals()), 1)

        // 23:30 in New York is already December in UTC; the count still follows the local month.
        let lateNovember = try date(counter, 2026, 11, 30, 23, 30)
        XCTAssertEqual(counter.monthKey(for: lateNovember), "2026-11")
        let november = counter.progress(for: goal, today: lateNovember, prayedDays: days, dhikr: DhikrTotals())
        XCTAssertEqual(november.count, 2)
        XCTAssertTrue(november.isComplete)

        let firstOfDecember = try date(counter, 2026, 12, 1, 0, 10)
        XCTAssertEqual(counter.count(for: goal, today: firstOfDecember, prayedDays: days, dhikr: DhikrTotals()), 1)
    }

    func testCelebrationHappensOncePerPeriod() throws {
        let counter = GoalCounter(timeZone: try newYork())
        var goal = PersonalGoal(kind: .fajrThisMonth, target: 1, startKey: "2026-11-01")
        let days: [String: Set<Prayer>] = ["2026-11-02": [.fajr], "2026-12-03": [.fajr]]
        let november = try date(counter, 2026, 11, 20)
        let progress = counter.progress(for: goal, today: november, prayedDays: days, dhikr: DhikrTotals())
        XCTAssertTrue(counter.needsCelebration(goal, progress: progress, today: november))

        goal.celebratedPeriod = counter.period(for: goal, today: november)
        XCTAssertEqual(goal.celebratedPeriod, "2026-11")
        XCTAssertFalse(counter.needsCelebration(goal, progress: progress, today: november))

        let december = try date(counter, 2026, 12, 5)
        let next = counter.progress(for: goal, today: december, prayedDays: days, dhikr: DhikrTotals())
        XCTAssertTrue(counter.needsCelebration(goal, progress: next, today: december), "a new month can be celebrated again")

        let open = PersonalGoal(kind: .nightPrayer, target: 40, startKey: "2026-11-01")
        XCTAssertEqual(counter.period(for: open, today: november), counter.period(for: open, today: december))
    }

    // MARK: - No deadline, gaps forgiven

    func testOnePrayerADayCountsAnyMarkedPrayer() throws {
        let counter = GoalCounter(timeZone: try newYork())
        let goal = PersonalGoal(kind: .onePrayerDays, target: 7, startKey: "2026-11-03")
        let days: [String: Set<Prayer>] = [
            "2026-11-01": [.fajr],
            "2026-11-03": [.maghrib],
            "2026-11-05": [],
            "2026-11-08": [.fajr, .isha]
        ]
        let today = try date(counter, 2026, 11, 10)
        XCTAssertEqual(counter.count(for: goal, today: today, prayedDays: days, dhikr: DhikrTotals()), 2)
        XCTAssertEqual(goal.title, "One prayer a day, 7 days")
        XCTAssertFalse(GoalKind.onePrayerDays.isManual)
    }

    func testAllFiveDaysHasNoDeadlineAndForgivesGaps() throws {
        let counter = GoalCounter(timeZone: try newYork())
        let goal = PersonalGoal(kind: .allFiveDays, target: 3, startKey: "2026-11-03")
        let everyPrayer = Set(Prayer.allCases)
        let days: [String: Set<Prayer>] = [
            "2026-11-01": everyPrayer,
            "2026-11-03": everyPrayer,
            "2026-11-07": everyPrayer,
            "2026-11-10": [.fajr, .dhuhr, .asr, .maghrib],
            "2026-12-20": everyPrayer
        ]

        let soon = try date(counter, 2026, 11, 12)
        XCTAssertEqual(counter.count(for: goal, today: soon, prayedDays: days, dhikr: DhikrTotals()), 2, "days before the goal began and partial days do not count")

        let muchLater = try date(counter, 2027, 6, 1)
        let progress = counter.progress(for: goal, today: muchLater, prayedDays: days, dhikr: DhikrTotals())
        XCTAssertEqual(progress.count, 3, "weeks of gaps never reset the count")
        XCTAssertTrue(progress.isComplete)
    }

    func testNightPrayerBelongsToTheEveningItBegan() throws {
        let counter = GoalCounter(timeZone: try newYork())
        XCTAssertEqual(counter.nightKey(for: try date(counter, 2026, 11, 10, 3, 0)), "2026-11-09")
        XCTAssertEqual(counter.nightKey(for: try date(counter, 2026, 11, 10, 11, 59)), "2026-11-09")
        XCTAssertEqual(counter.nightKey(for: try date(counter, 2026, 11, 10, 12, 0)), "2026-11-10")
        XCTAssertEqual(counter.nightKey(for: try date(counter, 2026, 11, 10, 22, 0)), "2026-11-10")
        XCTAssertEqual(counter.nightKey(for: try date(counter, 2026, 11, 1, 2, 0)), "2026-10-31")

        let goal = PersonalGoal(
            kind: .nightPrayer,
            target: 40,
            startKey: "2026-11-01",
            loggedKeys: ["2026-11-02", "2026-11-09", "2026-11-09", "2026-11-30"]
        )
        let today = try date(counter, 2027, 1, 1)
        XCTAssertEqual(counter.count(for: goal, today: today, prayedDays: [:], dhikr: DhikrTotals()), 3)
    }

    func testCustomGoalCountsItsManualCount() throws {
        let counter = GoalCounter(timeZone: try newYork())
        let goal = PersonalGoal(kind: .custom, name: "Read a page", target: 10, startKey: "2026-11-01", manualCount: 4)
        XCTAssertEqual(goal.title, "Read a page")
        let progress = counter.progress(for: goal, today: try date(counter, 2026, 11, 2), prayedDays: [:], dhikr: DhikrTotals())
        XCTAssertEqual(progress, GoalProgress(count: 4, target: 10))
        XCTAssertEqual(PersonalGoal(kind: .custom, target: 10, startKey: "2026-11-01", manualCount: -3).manualCount, 0)
    }

    // MARK: - Dhikr totals

    func testDhikrTotalsRollOverAtLocalMidnight() throws {
        let counter = GoalCounter(timeZone: try newYork(), firstWeekday: 2)
        let store = DhikrLogStore(defaults: try makeDefaults(), counter: counter)

        let beforeMidnight = try date(counter, 2026, 11, 10, 23, 59, 30)
        let afterMidnight = try date(counter, 2026, 11, 11, 0, 0, 30)
        for _ in 0..<5 {
            store.add(1, at: beforeMidnight)
        }
        store.add(3, at: afterMidnight)

        let totals = store.load()
        XCTAssertEqual(totals.total(on: "2026-11-10"), 5)
        XCTAssertEqual(totals.total(on: "2026-11-11"), 3)

        let today = PersonalGoal(kind: .dhikrToday, target: 100, startKey: "2026-11-10")
        XCTAssertEqual(counter.count(for: today, today: afterMidnight, prayedDays: [:], dhikr: totals), 3)
        XCTAssertEqual(counter.count(for: today, today: beforeMidnight, prayedDays: [:], dhikr: totals), 5)
        XCTAssertEqual(counter.period(for: today, today: afterMidnight), "2026-11-11")
    }

    func testDhikrWeekSumsTheCalendarWeek() throws {
        // Weeks start on Monday here. Nov 9, 2026 is a Monday and Nov 15 a Sunday.
        let counter = GoalCounter(timeZone: try newYork(), firstWeekday: 2)
        let totals = DhikrTotals(byDay: [
            "2026-11-08": 1000,
            "2026-11-09": 33,
            "2026-11-12": 100,
            "2026-11-15": 7,
            "2026-11-16": 500
        ])
        let wednesday = try date(counter, 2026, 11, 11)
        XCTAssertEqual(counter.weekKeys(containing: wednesday).first, "2026-11-09")
        XCTAssertEqual(counter.weekKeys(containing: wednesday).last, "2026-11-15")

        let goal = PersonalGoal(kind: .dhikrWeek, target: 100, startKey: "2026-11-01")
        XCTAssertEqual(counter.count(for: goal, today: wednesday, prayedDays: [:], dhikr: totals), 140)
        XCTAssertEqual(counter.period(for: goal, today: wednesday), "2026-11-09")

        let nextMonday = try date(counter, 2026, 11, 16, 0, 5)
        XCTAssertEqual(counter.count(for: goal, today: nextMonday, prayedDays: [:], dhikr: totals), 500)
    }

    func testLastDaysAreOldestFirstAcrossAClockChange() throws {
        // Clocks go back in New York on Nov 1, 2026.
        let counter = GoalCounter(timeZone: try newYork())
        let days = counter.lastDays(7, endingOn: try date(counter, 2026, 11, 3, 0, 30))
        XCTAssertEqual(days.map(counter.dayKey(for:)), [
            "2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"
        ])
    }

    func testDhikrStoreKeepsOnlyRecentDays() throws {
        let counter = GoalCounter(timeZone: try newYork())
        let store = DhikrLogStore(defaults: try makeDefaults(), counter: counter)
        store.add(10, at: try date(counter, 2026, 1, 1))
        store.add(4, at: try date(counter, 2026, 11, 20))
        let totals = store.load()
        XCTAssertEqual(totals.total(on: "2026-01-01"), 0)
        XCTAssertEqual(totals.total(on: "2026-11-20"), 4)

        var plain = DhikrTotals()
        plain.add(0, on: "2026-11-20")
        plain.add(-4, on: "2026-11-20")
        XCTAssertEqual(plain, DhikrTotals())
    }

    // MARK: - Store

    func testGoalStoreRoundTrip() throws {
        let store = GoalStore(defaults: try makeDefaults())
        XCTAssertEqual(store.load(), [])

        let first = PersonalGoal(kind: .nightPrayer, target: 40, startKey: "2026-11-01")
        let second = PersonalGoal(kind: .custom, name: "Visit family", target: 4, startKey: "2026-11-02")
        store.add(first)
        store.add(second)
        XCTAssertEqual(store.load(), [first, second])

        var logged = first
        logged.loggedKeys = ["2026-11-01"]
        store.update(logged)
        XCTAssertEqual(store.load().first?.loggedKeys, ["2026-11-01"])

        store.remove(id: second.id)
        XCTAssertEqual(store.load(), [logged])
    }

    func testDayKeysMatchPrayedStore() throws {
        let zone = try newYork()
        let counter = GoalCounter(timeZone: zone)
        let prayed = PrayedStore(defaults: try makeDefaults(), timeZone: zone)
        let instant = try date(counter, 2026, 11, 30, 23, 45)
        XCTAssertEqual(counter.dayKey(for: instant), prayed.dayKey(for: instant))
    }
}
