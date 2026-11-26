import XCTest
@testable import FiveSkies

final class MoreToolsTests: XCTestCase {
    // MARK: - Streaks

    private func utc() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func makeToday(_ calculator: StreakCalculator) throws -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 26
        components.hour = 21
        return try XCTUnwrap(calculator.calendar.date(from: components))
    }

    private func keys(_ calculator: StreakCalculator, today: Date, daysAgo: [Int]) throws -> Set<String> {
        var result: Set<String> = []
        for offset in daysAgo {
            let date = try XCTUnwrap(calculator.calendar.date(byAdding: .day, value: -offset, to: today))
            result.insert(calculator.dayKey(for: date))
        }
        return result
    }

    func testStreakIsZeroForEmptyHistory() throws {
        let calculator = StreakCalculator(timeZone: try utc())
        let today = try makeToday(calculator)
        XCTAssertEqual(calculator.currentStreak(completedDays: [], today: today), 0)
        XCTAssertEqual(calculator.bestStreak(completedDays: []), 0)
    }

    func testStreakEndingToday() throws {
        let calculator = StreakCalculator(timeZone: try utc())
        let today = try makeToday(calculator)
        let days = try keys(calculator, today: today, daysAgo: [0, 1, 2])
        XCTAssertEqual(calculator.currentStreak(completedDays: days, today: today), 3)
    }

    func testStreakEndsYesterdayWhenTodayIsIncomplete() throws {
        let calculator = StreakCalculator(timeZone: try utc())
        let today = try makeToday(calculator)
        let days = try keys(calculator, today: today, daysAgo: [1, 2, 3, 4])
        XCTAssertEqual(calculator.currentStreak(completedDays: days, today: today), 4)
    }

    func testGapBreaksTheStreak() throws {
        let calculator = StreakCalculator(timeZone: try utc())
        let today = try makeToday(calculator)
        let days = try keys(calculator, today: today, daysAgo: [0, 1, 3, 4, 5])
        XCTAssertEqual(calculator.currentStreak(completedDays: days, today: today), 2)

        let olderOnly = try keys(calculator, today: today, daysAgo: [2, 3])
        XCTAssertEqual(calculator.currentStreak(completedDays: olderOnly, today: today), 0)
    }

    func testBestStreakFindsTheLongestRun() throws {
        let calculator = StreakCalculator(timeZone: try utc())
        let today = try makeToday(calculator)
        let days = try keys(calculator, today: today, daysAgo: [0, 1, 5, 6, 7, 8, 20, 40, 41, 42])
        XCTAssertEqual(calculator.bestStreak(completedDays: days), 4)
        XCTAssertEqual(calculator.currentStreak(completedDays: days, today: today), 2)
    }

    func testBestStreakCrossesMonthAndYearBoundaries() {
        let calculator = StreakCalculator(timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
        let days: Set<String> = ["2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "not-a-key"]
        XCTAssertEqual(calculator.bestStreak(completedDays: days), 4)
    }

    func testStreakKeysMatchPrayedStoreKeys() throws {
        let zone = try utc()
        let calculator = StreakCalculator(timeZone: zone)
        let store = PrayedStore(defaults: UserDefaults(), timeZone: zone)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(calculator.dayKey(for: date), store.dayKey(for: date))
    }

    func testCompleteDayKeysNeedsAllFivePrayers() throws {
        let suite = "MoreToolsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let zone = try utc()
        let store = PrayedStore(defaults: defaults, timeZone: zone)
        let full = Date(timeIntervalSince1970: 1_800_000_000)
        let partial = full.addingTimeInterval(24 * 3600)
        for prayer in Prayer.allCases {
            store.setPrayed(true, prayer, on: full)
        }
        store.setPrayed(true, .fajr, on: partial)

        XCTAssertEqual(PrayedStore.completeDayKeys(in: defaults), [store.dayKey(for: full)])
    }

    // MARK: - Tasbih

    func testTasbihIncrementsAndWrapsAtEachTarget() {
        for target in TasbihCounter.targets {
            var counter = TasbihCounter(count: 0, target: target, rounds: 0)
            for _ in 0..<(target - 1) {
                counter.increment()
            }
            XCTAssertEqual(counter.count, target - 1)
            XCTAssertEqual(counter.rounds, 0)

            counter.increment()
            XCTAssertEqual(counter.count, target, "target \(target)")
            XCTAssertEqual(counter.rounds, 1, "target \(target)")
            XCTAssertEqual(counter.progress, 1, accuracy: 0.0001)

            counter.increment()
            XCTAssertEqual(counter.count, 1, "target \(target) should wrap to a new round")
            XCTAssertEqual(counter.rounds, 1)
        }
    }

    func testTasbihResetAndTargetChange() {
        var counter = TasbihCounter(count: 50, target: 99, rounds: 2)
        counter.setTarget(33)
        XCTAssertEqual(counter.target, 33)
        XCTAssertEqual(counter.count, 0)

        counter.increment()
        counter.reset()
        XCTAssertEqual(counter, TasbihCounter(count: 0, target: 33, rounds: 0))

        counter.setTarget(7)
        XCTAssertEqual(counter.target, 33, "only 33, 99 and 100 are allowed")
        XCTAssertEqual(TasbihCounter(count: 0, target: 12, rounds: 0).target, TasbihCounter.defaultTarget)
    }

    // MARK: - Zakat

    func testZakatBasicCase() {
        let inputs = ZakatInputs(cash: 10_000, goldAndSilver: 2_000, investments: 5_000, owedToYou: 1_000, debts: 2_000)
        XCTAssertEqual(ZakatCalculator.netWealth(inputs), 16_000)
        XCTAssertEqual(ZakatCalculator.zakatDue(inputs), 400)
    }

    func testZakatIsZeroWhenDebtsExceedAssets() {
        let inputs = ZakatInputs(cash: 1_000, goldAndSilver: 0, investments: 0, owedToYou: 0, debts: 5_000)
        XCTAssertEqual(ZakatCalculator.zakatDue(inputs), 0)
    }

    func testZakatKeepsDecimalPrecision() throws {
        let cash = try XCTUnwrap(Decimal(string: "0.1", locale: Locale(identifier: "en_US_POSIX")))
        let gold = try XCTUnwrap(Decimal(string: "0.2", locale: Locale(identifier: "en_US_POSIX")))
        let big = try XCTUnwrap(Decimal(string: "1000.10", locale: Locale(identifier: "en_US_POSIX")))
        let inputs = ZakatInputs(cash: cash + gold + big, goldAndSilver: 0, investments: 0, owedToYou: 0, debts: 0)
        let expected = try XCTUnwrap(Decimal(string: "25.01", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(ZakatCalculator.netWealth(inputs), cash + gold + big)
        XCTAssertEqual(ZakatCalculator.zakatDue(inputs), expected)
    }

    func testZakatParsesLocaleAmounts() throws {
        let us = Locale(identifier: "en_US")
        let expected = try XCTUnwrap(Decimal(string: "1234.5", locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertEqual(ZakatCalculator.parse("1,234.50", locale: us), expected)
        XCTAssertEqual(ZakatCalculator.parse("1234,50", locale: Locale(identifier: "de_DE")), expected)
        XCTAssertEqual(ZakatCalculator.parse("", locale: us), 0)
        XCTAssertEqual(ZakatCalculator.parse("abc", locale: us), 0)
    }

    // MARK: - Hijri

    func testHijriConversionGivesSaneComponents() throws {
        let math = HijriCalendarMath(timeZone: try utc(), locale: Locale(identifier: "en_US"))
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        for _ in 0..<60 {
            let parts = math.hijriComponents(for: date)
            let month = try XCTUnwrap(parts.month)
            let day = try XCTUnwrap(parts.day)
            XCTAssertTrue((1...12).contains(month), "month \(month)")
            XCTAssertTrue((1...30).contains(day), "day \(day)")
            date = date.addingTimeInterval(13 * 24 * 3600)
        }
    }

    func testMonthGridHasOneSlotPerDayAfterLeadingBlanks() throws {
        let math = HijriCalendarMath(timeZone: try utc(), locale: Locale(identifier: "en_US"))
        let start = math.monthStart(containing: Date(timeIntervalSince1970: 1_800_000_000))
        let slots = math.slots(forMonthStarting: start)
        let days = slots.compactMap(\.cell)
        let expectedCount = try XCTUnwrap(math.gregorian.range(of: .day, in: .month, for: start)).count
        XCTAssertEqual(days.count, expectedCount)
        XCTAssertEqual(days.first?.gregorianDay, 1)
        XCTAssertLessThan(slots.count - days.count, 7)
        XCTAssertEqual(math.weekdaySymbols.count, 7)
    }
}
