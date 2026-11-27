import XCTest
@testable import FiveSkies

final class RamadanTests: XCTestCase {
    private func utc() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func ummAlQura() throws -> Calendar {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = try utc()
        return calendar
    }

    private func gregorianDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try utc()
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return try XCTUnwrap(calendar.date(from: components))
    }

    /// Fixed dates spread over several years, so some fall in Ramadan and most do not.
    private func sampleDates() throws -> [Date] {
        var result: [Date] = []
        for year in 2024...2028 {
            for month in 1...12 {
                result.append(try gregorianDate(year, month, 15))
            }
        }
        return result
    }

    // MARK: - Next Ramadan

    func testNextRamadanIsFirstOfRamadanInTheFutureWithinAHijriYear() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        for date in try sampleDates() {
            let upcoming = try XCTUnwrap(math.nextRamadan(after: date))
            let parts = calendar.dateComponents([.year, .month, .day], from: upcoming.start)
            XCTAssertEqual(parts.month, 9)
            XCTAssertEqual(parts.day, 1)
            XCTAssertEqual(parts.year, upcoming.hijriYear)
            XCTAssertGreaterThan(upcoming.start, date)
            XCTAssertGreaterThanOrEqual(upcoming.daysAway, 1)
            XCTAssertLessThanOrEqual(upcoming.daysAway, 355)
            XCTAssertLessThanOrEqual(upcoming.start.timeIntervalSince(date), 355 * 86_400)
        }
    }

    func testDayBeforeRamadanIsOneDayAway() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        let upcoming = try XCTUnwrap(math.nextRamadan(after: try gregorianDate(2026, 6, 1)))
        let dayBefore = try XCTUnwrap(calendar.date(byAdding: .hour, value: -12, to: upcoming.start))
        let next = try XCTUnwrap(math.nextRamadan(after: dayBefore))
        XCTAssertEqual(next.start, upcoming.start)
        XCTAssertEqual(next.daysAway, 1)
    }

    func testDuringRamadanTheNextStartIsNextYear() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        let first = try XCTUnwrap(math.nextRamadan(after: try gregorianDate(2026, 6, 1)))
        let inside = try XCTUnwrap(calendar.date(byAdding: .hour, value: 36, to: first.start))
        let next = try XCTUnwrap(math.nextRamadan(after: inside))
        XCTAssertEqual(next.hijriYear, first.hijriYear + 1)
        XCTAssertGreaterThan(next.start, inside)
        XCTAssertLessThanOrEqual(next.daysAway, 355)
    }

    // MARK: - Day of Ramadan

    func testDayOfRamadanInsideRamadan() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        let start = try XCTUnwrap(math.nextRamadan(after: try gregorianDate(2026, 6, 1))).start
        for offset in 0..<29 {
            let date = try XCTUnwrap(calendar.date(byAdding: .hour, value: 24 * offset + 12, to: start))
            let day = try XCTUnwrap(math.dayOfRamadan(on: date))
            XCTAssertTrue((1...30).contains(day))
            XCTAssertEqual(day, offset + 1)
            XCTAssertTrue(math.isRamadan(date))
            XCTAssertEqual(calendar.component(.month, from: date), 9)
        }
    }

    func testDayOfRamadanMatchesCalendarForSampleDates() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        for date in try sampleDates() {
            let parts = calendar.dateComponents([.month, .day], from: date)
            if parts.month == 9 {
                let day = try XCTUnwrap(math.dayOfRamadan(on: date))
                XCTAssertTrue((1...30).contains(day))
                XCTAssertEqual(day, parts.day)
            } else {
                XCTAssertNil(math.dayOfRamadan(on: date))
            }
        }
    }

    func testDayBeforeRamadanIsNotRamadan() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        let start = try XCTUnwrap(math.nextRamadan(after: try gregorianDate(2027, 6, 1))).start
        let dayBefore = try XCTUnwrap(calendar.date(byAdding: .hour, value: -12, to: start))
        XCTAssertNil(math.dayOfRamadan(on: dayBefore))
        XCTAssertFalse(math.isRamadan(dayBefore))
    }

    func testLogYearIsTheCurrentOrUpcomingRamadan() throws {
        let calendar = try ummAlQura()
        let math = RamadanCalendar(calendar: calendar)
        for date in try sampleDates() {
            let year = try XCTUnwrap(math.logYear(for: date))
            if let day = math.dayOfRamadan(on: date) {
                XCTAssertTrue((1...30).contains(day))
                XCTAssertEqual(year, calendar.component(.year, from: date))
            } else {
                let upcoming = try XCTUnwrap(math.nextRamadan(after: date))
                XCTAssertEqual(year, upcoming.hijriYear)
            }
        }
    }

    func testHijriDateTextEndsWithAH() throws {
        let math = RamadanCalendar(calendar: try ummAlQura())
        let text = math.hijriDateText(for: try gregorianDate(2026, 11, 26))
        XCTAssertTrue(text.hasSuffix(" AH"))
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: - Suhoor and Iftar

    func testNextTargetMovesFromSuhoorToIftarToTomorrow() throws {
        let base = try gregorianDate(2026, 3, 1, hour: 0)
        let day = PrayerDay(
            fajr: base.addingTimeInterval(5 * 3600),
            sunrise: base.addingTimeInterval(6 * 3600),
            dhuhr: base.addingTimeInterval(12 * 3600),
            asr: base.addingTimeInterval(15 * 3600),
            maghrib: base.addingTimeInterval(18 * 3600),
            isha: base.addingTimeInterval(19 * 3600),
            tomorrowFajr: base.addingTimeInterval(29 * 3600)
        )
        let early = RamadanTimes.next(after: base.addingTimeInterval(3600), in: day)
        XCTAssertEqual(early, RamadanTarget(moment: .suhoorEnds, time: day.fajr))
        let midday = RamadanTimes.next(after: base.addingTimeInterval(13 * 3600), in: day)
        XCTAssertEqual(midday, RamadanTarget(moment: .iftar, time: day.maghrib))
        let night = RamadanTimes.next(after: base.addingTimeInterval(20 * 3600), in: day)
        XCTAssertEqual(night, RamadanTarget(moment: .suhoorEnds, time: day.tomorrowFajr))
    }

    func testCountdownText() throws {
        let now = try gregorianDate(2026, 3, 1)
        XCTAssertEqual(RamadanTimes.countdown(from: now, to: now.addingTimeInterval(30)), "1m")
        XCTAssertEqual(RamadanTimes.countdown(from: now, to: now.addingTimeInterval(72 * 60)), "1h 12m")
    }

    // MARK: - Fasting log store

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "RamadanTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    func testFastingLogRoundTrip() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FastingLogStore(defaults: defaults)
        XCTAssertTrue(store.fastedDays(inRamadanOf: 1448).isEmpty)
        store.setFasted(true, day: 1, year: 1448)
        store.setFasted(true, day: 7, year: 1448)
        store.setFasted(true, day: 30, year: 1448)
        store.setFasted(true, day: 3, year: 1449)
        store.setFasted(true, day: 31, year: 1448)
        store.setFasted(true, day: 0, year: 1448)

        let reloaded = FastingLogStore(defaults: defaults)
        XCTAssertEqual(reloaded.fastedDays(inRamadanOf: 1448), [1, 7, 30])
        XCTAssertEqual(reloaded.fastedDays(inRamadanOf: 1449), [3])
        XCTAssertTrue(reloaded.isFasted(day: 7, year: 1448))
        XCTAssertFalse(reloaded.isFasted(day: 7, year: 1449))

        reloaded.setFasted(false, day: 7, year: 1448)
        XCTAssertEqual(FastingLogStore(defaults: defaults).fastedDays(inRamadanOf: 1448), [1, 30])
    }

    func testVoluntaryFastsAndTaraweehRoundTrip() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FastingLogStore(defaults: defaults)
        let monday = HijriDay(year: 1448, month: 5, day: 16)
        let thursday = HijriDay(year: 1448, month: 5, day: 19)
        XCTAssertEqual(store.voluntaryFastCount, 0)
        store.setVoluntaryFast(true, on: monday)
        store.setVoluntaryFast(true, on: thursday)
        store.setVoluntaryFast(true, on: thursday)

        let reloaded = FastingLogStore(defaults: defaults)
        XCTAssertEqual(reloaded.voluntaryFastCount, 2)
        XCTAssertTrue(reloaded.isVoluntaryFastLogged(on: monday))
        reloaded.setVoluntaryFast(false, on: monday)
        XCTAssertEqual(FastingLogStore(defaults: defaults).voluntaryFastCount, 1)
        XCTAssertFalse(FastingLogStore(defaults: defaults).isVoluntaryFastLogged(on: monday))

        let night = HijriDay(year: 1448, month: 9, day: 3)
        XCTAssertFalse(reloaded.prayedTaraweeh(on: night))
        reloaded.setTaraweeh(true, on: night)
        XCTAssertTrue(FastingLogStore(defaults: defaults).prayedTaraweeh(on: night))
        XCTAssertFalse(FastingLogStore(defaults: defaults).prayedTaraweeh(on: HijriDay(year: 1448, month: 9, day: 4)))
        reloaded.setTaraweeh(false, on: night)
        XCTAssertFalse(FastingLogStore(defaults: defaults).prayedTaraweeh(on: night))
    }

    func testHijriDayKey() {
        XCTAssertEqual(HijriDay(year: 1448, month: 9, day: 1).key, "1448-09-01")
    }
}
