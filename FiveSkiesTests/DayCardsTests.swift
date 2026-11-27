import XCTest
@testable import FiveSkies

/// Fixed dates were checked against the Umm al-Qura calendar (ICU, the same data Foundation uses).
final class DayCardsTests: XCTestCase {
    private func utc() throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: "UTC"))
    }

    private func rules(adjustment: Int = 0) throws -> DayCardRules {
        DayCardRules(timeZone: try utc(), hijriAdjustment: adjustment)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try utc()
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func kinds(_ year: Int, _ month: Int, _ day: Int, adjustment: Int = 0) throws -> [DayCardKind] {
        try rules(adjustment: adjustment).cards(for: try date(year, month, day)).map(\.kind)
    }

    // MARK: - Single reminders

    func testFridayOnly() throws {
        // Friday 27 November 2026 is 17 Jumada II 1448.
        let cards = try rules().cards(for: try date(2026, 11, 27))
        XCTAssertEqual(cards.map(\.kind), [.friday])
        XCTAssertEqual(cards.first?.title, "It is Friday")
    }

    func testWhiteDay() throws {
        // Wednesday 26 August 2026 is 13 Rabi I 1448.
        let cards = try rules().cards(for: try date(2026, 8, 26))
        XCTAssertEqual(cards.map(\.kind), [.whiteDay])
        XCTAssertEqual(cards.first?.title, "One of the white days")
    }

    func testRamadanDayNumber() throws {
        // Sunday 1 March 2026 is 12 Ramadan 1447.
        let cards = try rules().cards(for: try date(2026, 3, 1))
        XCTAssertEqual(cards.map(\.kind), [.ramadan])
        XCTAssertEqual(cards.first?.title, "Ramadan, day 12")
        XCTAssertNil(cards.first?.subtitle)
    }

    func testRamadanLastTenDaysWithFriday() throws {
        // Friday 13 March 2026 is 24 Ramadan 1447.
        let cards = try rules().cards(for: try date(2026, 3, 13))
        XCTAssertEqual(cards.map(\.kind), [.ramadan, .friday])
        XCTAssertEqual(cards.first?.title, "Ramadan, day 24")
        XCTAssertEqual(cards.first?.subtitle, "The last ten days")
    }

    func testMonday() throws {
        // Monday 21 September 2026 is 10 Rabi II 1448.
        let cards = try rules().cards(for: try date(2026, 9, 21))
        XCTAssertEqual(cards.map(\.kind), [.monday])
        XCTAssertEqual(cards.first?.title, "It is Monday")
    }

    func testThursday() throws {
        // Thursday 26 November 2026 is 16 Jumada II 1448.
        let cards = try rules().cards(for: try date(2026, 11, 26))
        XCTAssertEqual(cards.map(\.kind), [.thursday])
        XCTAssertEqual(cards.first?.title, "It is Thursday")
    }

    func testTuesdayOutsideAnySpecialDayShowsNothing() throws {
        // Tuesday 25 August 2026 is 12 Rabi I 1448.
        XCTAssertEqual(try kinds(2026, 8, 25), [])
    }

    // MARK: - Eid and Arafah

    func testEidAlFitrComesBeforeFriday() throws {
        // Friday 20 March 2026 is 1 Shawwal 1447.
        let cards = try rules().cards(for: try date(2026, 3, 20))
        XCTAssertEqual(cards.map(\.kind), [.eidAlFitr, .friday])
        XCTAssertEqual(cards.first?.title, "Eid al-Fitr")
    }

    func testEidAlAdha() throws {
        // Wednesday 27 May 2026 is 10 Dhu al-Hijjah 1447.
        XCTAssertEqual(try kinds(2026, 5, 27), [.eidAlAdha])
    }

    func testDayOfArafah() throws {
        // Tuesday 26 May 2026 is 9 Dhu al-Hijjah 1447.
        XCTAssertEqual(try kinds(2026, 5, 26), [.dayOfArafah])
    }

    // MARK: - Fasting notes stay out of Ramadan and the Eid days

    func testMondayInRamadanShowsOnlyRamadan() throws {
        // Monday 2 March 2026 is 13 Ramadan 1447: a white day number and a Monday, but Ramadan.
        XCTAssertEqual(try kinds(2026, 3, 2), [.ramadan])
    }

    func testFastingNotesRule() {
        XCTAssertTrue(DayCardRules.fastingNotesApply(on: HijriDay(year: 1448, month: 3, day: 13)))
        XCTAssertFalse(DayCardRules.fastingNotesApply(on: HijriDay(year: 1448, month: 9, day: 13)))
        XCTAssertFalse(DayCardRules.fastingNotesApply(on: HijriDay(year: 1448, month: 10, day: 1)))
        XCTAssertFalse(DayCardRules.fastingNotesApply(on: HijriDay(year: 1448, month: 12, day: 13)))
        XCTAssertTrue(DayCardRules.fastingNotesApply(on: HijriDay(year: 1448, month: 12, day: 14)))
    }

    // MARK: - Hijri adjustment

    func testAdjustmentMovesADayIntoTheWhiteDays() throws {
        // 12 Rabi I 1448; one day later on the Hijri side is 13.
        XCTAssertEqual(try kinds(2026, 8, 25, adjustment: 0), [])
        XCTAssertEqual(try kinds(2026, 8, 25, adjustment: 1), [.whiteDay])
        // Saturday 29 August 2026 is 16 Rabi I 1448; one day earlier is 15.
        XCTAssertEqual(try kinds(2026, 8, 29, adjustment: 0), [])
        XCTAssertEqual(try kinds(2026, 8, 29, adjustment: -1), [.whiteDay])
    }

    func testAdjustmentMovesADayOutOfTheWhiteDays() throws {
        // Friday 28 August 2026 is 15 Rabi I 1448; a day later is 16, still a Friday.
        XCTAssertEqual(try kinds(2026, 8, 28, adjustment: 0), [.friday, .whiteDay])
        XCTAssertEqual(try kinds(2026, 8, 28, adjustment: 1), [.friday])
        // Wednesday 26 August 2026 is 13 Rabi I 1448; a day earlier is 12.
        XCTAssertEqual(try kinds(2026, 8, 26, adjustment: -1), [])
    }

    func testAdjustmentIsClamped() throws {
        XCTAssertEqual(try rules(adjustment: 9).hijriAdjustment, 2)
        XCTAssertEqual(try rules(adjustment: -9).hijriAdjustment, -2)
    }

    func testAdjustmentMovesRamadanDay() throws {
        let card = try rules(adjustment: 1).cards(for: try date(2026, 3, 1)).first
        XCTAssertEqual(card?.title, "Ramadan, day 13")
    }

    // MARK: - Limits, hiding and time zones

    func testAtMostTwoAndHidingShowsTheRest() throws {
        // Monday 23 November 2026 is 13 Jumada II 1448: a white day and a Monday.
        let subject = try rules()
        let day = try date(2026, 11, 23)
        XCTAssertEqual(subject.cards(for: day).map(\.kind), [.whiteDay, .monday])
        XCTAssertEqual(subject.cards(for: day, hiding: ["whiteDay"]).map(\.kind), [.monday])
        XCTAssertLessThanOrEqual(subject.cards(for: day).count, DayCardRules.maxShown)
    }

    func testNeverMoreThanTwoAcrossTwoYears() throws {
        let subject = try rules()
        let start = try date(2026, 1, 1)
        for offset in 0..<730 {
            let day = start.addingTimeInterval(Double(offset) * 86_400)
            XCTAssertLessThanOrEqual(subject.cards(for: day).count, DayCardRules.maxShown)
        }
    }

    func testWeekdayFollowsTheTimeZone() throws {
        // 23:30 UTC on Friday 27 November 2026 is already Saturday in Riyadh.
        let riyadh = try XCTUnwrap(TimeZone(identifier: "Asia/Riyadh"))
        let late = try date(2026, 11, 27, hour: 23, minute: 30)
        XCTAssertEqual(try rules().cards(for: late).map(\.kind), [.friday])
        XCTAssertEqual(DayCardRules(timeZone: riyadh).cards(for: late).map(\.kind), [])
        XCTAssertEqual(DayCardRules(timeZone: riyadh).dayKey(for: late), "2026-11-28")
        XCTAssertEqual(try rules().dayKey(for: late), "2026-11-27")
    }

    func testCopyHasNoEmDashes() {
        var cards = DayCardKind.allCases.map { DayCardRules.card($0) }
        cards.append(DayCardRules.ramadanCard(day: 25))
        for card in cards {
            XCTAssertFalse(card.title.contains("\u{2014}"))
            XCTAssertFalse((card.subtitle ?? "").contains("\u{2014}"))
            XCTAssertFalse(card.title.isEmpty)
        }
    }

    // MARK: - Dismissals

    func testDismissalsLastOneDay() throws {
        let suite = "DayCardsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DayCardDismissals(defaults: defaults)

        XCTAssertEqual(store.hidden(on: "2026-11-27"), [])
        store.hide("friday", on: "2026-11-27")
        store.hide("whiteDay", on: "2026-11-27")
        XCTAssertEqual(store.hidden(on: "2026-11-27"), ["friday", "whiteDay"])
        XCTAssertEqual(store.hidden(on: "2026-11-28"), [])

        store.hide("monday", on: "2026-11-30")
        XCTAssertEqual(store.hidden(on: "2026-11-30"), ["monday"])
        XCTAssertEqual(store.hidden(on: "2026-11-27"), [])
    }

    // MARK: - Launch hook

    func testLaunchHookAbsentByDefault() throws {
        let options = DayCardsLaunchOptions(arguments: ["FiveSkies", "-FSFixedPhase", "dhuhr"])
        XCTAssertNil(options.dateText)
        XCTAssertNil(options.date(in: try utc()))
    }

    func testLaunchHookParsesNoonOfTheDay() throws {
        let options = DayCardsLaunchOptions(arguments: ["FiveSkies", "-FSDayCardsDate", "2026-08-28"])
        XCTAssertEqual(options.date(in: try utc()), try date(2026, 8, 28))
    }

    func testLaunchHookRejectsBadDates() throws {
        let zone = try utc()
        XCTAssertNil(DayCardsLaunchOptions.parse("2026-02-30", timeZone: zone))
        XCTAssertNil(DayCardsLaunchOptions.parse("2026-8-28", timeZone: zone))
        XCTAssertNil(DayCardsLaunchOptions.parse("tomorrow", timeZone: zone))
        XCTAssertNil(DayCardsLaunchOptions(arguments: ["-FSDayCardsDate"]).dateText)
    }
}
