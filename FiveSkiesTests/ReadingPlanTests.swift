import XCTest
@testable import FiveSkies

final class ReadingPlanTests: XCTestCase {
    private var calendar: Calendar!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        calendar = fixed
        suiteName = "ReadingPlanTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        calendar = nil
    }

    /// A local time in the test calendar's time zone.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let value = calendar.date(from: components) else {
            XCTFail("Bad date")
            return Date()
        }
        return value
    }

    private func portion(next: Int, kind: ReadingPlanKind, start: Date, today: Date) -> ClosedRange<Int>? {
        ReadingPlanMath.todaysPortion(nextPage: next, kind: kind, startDate: start, today: today, calendar: calendar)
    }

    // MARK: - Math

    func testThirtyDayPlanFirstDay() {
        let start = date(2026, 6, 1)
        // 604 / 30 = 20.13, rounded up.
        XCTAssertEqual(portion(next: 1, kind: .days(30), start: start, today: start), 1...21)
        XCTAssertEqual(portion(next: 1, kind: .days(30), start: start, today: date(2026, 6, 1, 23, 59)), 1...21)
    }

    func testSkippedDaysSpreadTheRestAgain() {
        let start = date(2026, 6, 1)
        // Day 1 read (pages 1 to 21), then days 2 to 4 skipped. Day 5: 583 pages over 26 days.
        XCTAssertEqual(portion(next: 22, kind: .days(30), start: start, today: date(2026, 6, 5)), 22...44)
        // Had day 2 been read instead: 583 pages over 29 days.
        XCTAssertEqual(portion(next: 22, kind: .days(30), start: start, today: date(2026, 6, 2)), 22...42)
    }

    @MainActor
    func testSampleScreenshotPlan() {
        // The -FSPlanSample plan: 30 days, started 3 days ago, pages 1 to 60 read.
        let today = date(2026, 6, 4, 20)
        let sample = ReadingPlanStore.sample(now: today, calendar: calendar)
        XCTAssertEqual(sample.nextPage, 61)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: sample.startDate, to: today, calendar: calendar), 3)
        // 544 pages over 27 days = 20.1, rounded up.
        XCTAssertEqual(sample.portion(on: today, calendar: calendar), 61...81)
        XCTAssertEqual(ReadingPlanText.summary(plan: sample, today: today, calendar: calendar), "Today: pages 61 to 81")
    }

    func testLastDayTakesEverythingLeft() {
        let start = date(2026, 6, 1)
        let lastDay = date(2026, 6, 30)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: start, to: lastDay, calendar: calendar), 29)
        XCTAssertEqual(portion(next: 400, kind: .days(30), start: start, today: lastDay), 400...604)
        // After the end date, still everything left, never an error or a warning.
        XCTAssertEqual(portion(next: 400, kind: .days(30), start: start, today: date(2026, 8, 15)), 400...604)
    }

    func testAtLeastOnePageADay() {
        let start = date(2026, 1, 1)
        // 5 pages left over 300 days still gives a page today.
        XCTAssertEqual(portion(next: 600, kind: .days(365), start: start, today: date(2026, 1, 2)), 600...600)
    }

    func testTodayBeforeStartCountsAsTheFirstDay() {
        let start = date(2026, 6, 10)
        XCTAssertEqual(portion(next: 1, kind: .days(30), start: start, today: date(2026, 6, 8)), 1...21)
    }

    func testPace() {
        let start = date(2026, 6, 1)
        XCTAssertEqual(portion(next: 61, kind: .pace(pagesPerDay: 5), start: start, today: date(2026, 9, 1)), 61...65)
        XCTAssertEqual(portion(next: 1, kind: .pace(pagesPerDay: 1), start: start, today: start), 1...1)
        XCTAssertEqual(portion(next: 590, kind: .pace(pagesPerDay: 20), start: start, today: start), 590...604)
    }

    func testFinishedHasNoPortion() {
        let start = date(2026, 6, 1)
        XCTAssertNil(portion(next: 605, kind: .days(30), start: start, today: start))
        XCTAssertNil(portion(next: 605, kind: .pace(pagesPerDay: 5), start: start, today: start))
        XCTAssertNil(portion(next: 9999, kind: .days(60), start: start, today: start))
    }

    func testNeverPastTheLastPage() {
        let start = date(2026, 6, 1)
        for kind in [ReadingPlanKind.days(30), .days(60), .days(365), .pace(pagesPerDay: 1), .pace(pagesPerDay: 2),
                     .pace(pagesPerDay: 5), .pace(pagesPerDay: 10), .pace(pagesPerDay: 20)] {
            for next in [1, 300, 590, 600, 604] {
                for offset in [0, 1, 15, 29, 59, 364, 500] {
                    let today = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    guard let range = portion(next: next, kind: kind, start: start, today: today) else {
                        XCTFail("No portion for \(kind) at page \(next)")
                        continue
                    }
                    XCTAssertEqual(range.lowerBound, next)
                    XCTAssertLessThanOrEqual(range.upperBound, 604)
                }
            }
        }
    }

    func testDaylightSavingDaysCountOnce() {
        // In New York, clocks go forward on Mar 8, 2026 and back on Nov 1, 2026.
        let spring = date(2026, 3, 7, 23, 30)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: spring, to: date(2026, 3, 8, 0, 30), calendar: calendar), 1)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: spring, to: date(2026, 3, 8, 23, 30), calendar: calendar), 1)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: spring, to: date(2026, 3, 9, 0, 10), calendar: calendar), 2)

        let autumn = date(2026, 10, 31, 8)
        // Nov 1 has 25 hours; 23:30 on Nov 1 is still day 2 of the plan.
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: autumn, to: date(2026, 11, 1, 23, 30), calendar: calendar), 1)
        XCTAssertEqual(ReadingPlanMath.dayIndex(from: autumn, to: date(2026, 11, 2, 0, 10), calendar: calendar), 2)

        // A 30 day plan that started Mar 1: Mar 9 is day index 8, 22 days left.
        let start = date(2026, 3, 1, 21)
        XCTAssertEqual(portion(next: 101, kind: .days(30), start: start, today: date(2026, 3, 9, 0, 30)), 101...123)
    }

    func testPagesPerDayForFreshPlans() {
        XCTAssertEqual(ReadingPlanMath.pagesPerDay(forDays: 30), 21)
        XCTAssertEqual(ReadingPlanMath.pagesPerDay(forDays: 60), 11)
        XCTAssertEqual(ReadingPlanMath.pagesPerDay(forDays: 365), 2)
    }

    func testTextNeverMentionsBeingBehind() {
        XCTAssertEqual(ReadingPlanText.pages(12...31), "pages 12 to 31")
        XCTAssertEqual(ReadingPlanText.pages(604...604), "page 604")
        XCTAssertEqual(ReadingPlanText.todayLine(12...31), "Today: pages 12 to 31")
        XCTAssertEqual(ReadingPlanText.summary(plan: nil, today: Date(), calendar: calendar), "Make a reading plan")
        let words = [ReadingPlanText.makePlan, ReadingPlanText.doneForToday, ReadingPlanText.finished,
                     ReadingPlanKind.days(30).title, ReadingPlanKind.days(365).title, ReadingPlanKind.pace(pagesPerDay: 1).title]
        for line in words {
            XCTAssertFalse(line.lowercased().contains("behind"), line)
            XCTAssertFalse(line.lowercased().contains("missed"), line)
        }
    }

    func testKindStorageRoundTrip() {
        for kind in [ReadingPlanKind.days(30), .days(60), .days(365), .pace(pagesPerDay: 1), .pace(pagesPerDay: 20)] {
            XCTAssertEqual(ReadingPlanKind(storageValue: kind.storageValue), kind)
        }
        XCTAssertNil(ReadingPlanKind(storageValue: ""))
        XCTAssertNil(ReadingPlanKind(storageValue: "days:0"))
        XCTAssertNil(ReadingPlanKind(storageValue: "weeks:3"))
        XCTAssertNil(ReadingPlanKind(storageValue: "pace:x"))
    }

    // MARK: - Store

    @MainActor
    func testStoreStartsEmptyAndStarts() {
        let store = ReadingPlanStore(defaults: defaults)
        XCTAssertNil(store.plan)
        let today = date(2026, 6, 1)
        store.start(.days(30), today: today)
        XCTAssertEqual(store.plan?.nextPage, 1)
        XCTAssertEqual(store.portion(today: today, calendar: calendar), 1...21)
    }

    @MainActor
    func testMarkDoneOncePerDay() {
        let store = ReadingPlanStore(defaults: defaults)
        let today = date(2026, 6, 1, 8)
        store.start(.days(30), today: today)

        XCTAssertTrue(store.markTodayDone(today: today, calendar: calendar))
        XCTAssertEqual(store.plan?.nextPage, 22)
        XCTAssertTrue(store.isDoneToday(date(2026, 6, 1, 22), calendar: calendar))
        XCTAssertEqual(ReadingPlanText.summary(plan: store.plan, today: date(2026, 6, 1, 22), calendar: calendar), "Done for today")

        XCTAssertFalse(store.markTodayDone(today: date(2026, 6, 1, 22), calendar: calendar))
        XCTAssertEqual(store.plan?.nextPage, 22)

        let nextDay = date(2026, 6, 2, 7)
        XCTAssertFalse(store.isDoneToday(nextDay, calendar: calendar))
        XCTAssertTrue(store.markTodayDone(today: nextDay, calendar: calendar))
        XCTAssertEqual(store.plan?.nextPage, 43)
    }

    @MainActor
    func testFinishingAndStartingAgain() {
        let store = ReadingPlanStore(defaults: defaults)
        let start = date(2026, 6, 1)
        store.start(.pace(pagesPerDay: 20), today: start)
        var day = start
        var guardCount = 0
        while store.plan?.isFinished == false, guardCount < 100 {
            store.markTodayDone(today: day, calendar: calendar)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guardCount += 1
        }
        XCTAssertEqual(store.plan?.nextPage, 605)
        XCTAssertEqual(store.plan?.pagesRead, 604)
        XCTAssertNil(store.portion(today: day, calendar: calendar))
        XCTAssertEqual(ReadingPlanText.summary(plan: store.plan, today: day, calendar: calendar), "You finished the whole Quran")
        XCTAssertFalse(store.markTodayDone(today: day, calendar: calendar))

        store.startAgain(today: day)
        XCTAssertEqual(store.plan?.nextPage, 1)
        XCTAssertEqual(store.plan?.kind, .pace(pagesPerDay: 20))
        XCTAssertNil(store.plan?.lastDoneDate)
    }

    @MainActor
    func testChangePlanKeepsProgress() {
        let store = ReadingPlanStore(defaults: defaults)
        store.start(.days(30), today: date(2026, 6, 1))
        store.markTodayDone(today: date(2026, 6, 1), calendar: calendar)
        let later = date(2026, 6, 10)
        store.change(to: .days(60), today: later)
        XCTAssertEqual(store.plan?.nextPage, 22)
        XCTAssertEqual(store.plan?.kind, .days(60))
        // 583 pages over a fresh 60 days from today.
        XCTAssertEqual(store.portion(today: later, calendar: calendar), 22...31)
    }

    @MainActor
    func testStorePersistsUnderItsPrefix() {
        let store = ReadingPlanStore(defaults: defaults)
        let today = date(2026, 6, 1)
        store.start(.pace(pagesPerDay: 10), today: today)
        store.markTodayDone(today: today, calendar: calendar)

        let reopened = ReadingPlanStore(defaults: defaults)
        XCTAssertEqual(reopened.plan, store.plan)
        XCTAssertEqual(reopened.plan?.nextPage, 11)

        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(ReadingPlanStore.keyPrefix) }
        XCTAssertEqual(Set(keys), [
            ReadingPlanStore.kindKey,
            ReadingPlanStore.startDateKey,
            ReadingPlanStore.nextPageKey,
            ReadingPlanStore.lastDoneDateKey
        ])
        for key in [ReadingPlanStore.kindKey, ReadingPlanStore.startDateKey, ReadingPlanStore.nextPageKey, ReadingPlanStore.lastDoneDateKey] {
            XCTAssertTrue(key.hasPrefix("readingPlan."), key)
        }

        reopened.remove()
        XCTAssertNil(ReadingPlanStore(defaults: defaults).plan)
    }

    @MainActor
    func testStoredPageIsClamped() {
        defaults.set("days:30", forKey: ReadingPlanStore.kindKey)
        defaults.set(date(2026, 6, 1).timeIntervalSince1970, forKey: ReadingPlanStore.startDateKey)
        defaults.set(9999, forKey: ReadingPlanStore.nextPageKey)
        XCTAssertEqual(ReadingPlanStore(defaults: defaults).plan?.nextPage, 605)
        defaults.set(-4, forKey: ReadingPlanStore.nextPageKey)
        XCTAssertEqual(ReadingPlanStore(defaults: defaults).plan?.nextPage, 1)
    }
}
