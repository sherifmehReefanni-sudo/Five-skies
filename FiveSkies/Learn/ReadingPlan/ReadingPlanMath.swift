import Foundation

/// How a reading plan is paced: finish in a set number of days, or a set number of pages a day.
enum ReadingPlanKind: Hashable, Sendable {
    case days(Int)
    case pace(pagesPerDay: Int)

    /// The day plans offered: 30, 60 and 365 days.
    static let dayChoices = [30, 60, 365]
    /// The paces offered, in pages a day.
    static let paceChoices = [1, 2, 5, 10, 20]
    static let defaultPace = 5

    /// "days:30" or "pace:5", as stored in UserDefaults.
    var storageValue: String {
        switch self {
        case .days(let count):
            return "days:\(count)"
        case .pace(let pagesPerDay):
            return "pace:\(pagesPerDay)"
        }
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let number = Int(parts[1]), number > 0 else { return nil }
        switch String(parts[0]) {
        case "days":
            self = .days(number)
        case "pace":
            self = .pace(pagesPerDay: number)
        default:
            return nil
        }
    }

    /// "Finish in 30 days", "Finish in a year" or "5 pages a day".
    var title: String {
        switch self {
        case .days(let count):
            return count == 365 ? "Finish in a year" : "Finish in \(count) days"
        case .pace(let pagesPerDay):
            return ReadingPlanText.pagesPerDay(pagesPerDay)
        }
    }
}

/// The arithmetic of a reading plan. Pages are the 604 pages of the Madina mushaf, from the
/// bundled Tanzil metadata. Nothing here knows about missed days: what is left is simply
/// spread over the days that are left.
enum ReadingPlanMath {
    static let pageCount = 604
    /// The value of the next page once the whole Quran has been read.
    static let finishedPage = pageCount + 1

    /// Whole calendar days from the start day to today; 0 on the start day.
    /// Counts calendar dates, so a 23 or 25 hour day still counts as one day.
    static func dayIndex(from start: Date, to today: Date, calendar: Calendar) -> Int {
        let from = calendar.dateComponents([.year, .month, .day], from: start)
        let to = calendar.dateComponents([.year, .month, .day], from: today)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Today's pages, or nil once the whole Quran has been read.
    /// For a day plan: the pages left divided by the days left including today, rounded up,
    /// at least one page. The plan ends `count` days after the start day; on its last day or
    /// later, everything left is today's portion. For a pace plan: that many pages a day.
    /// Never goes past page 604.
    static func todaysPortion(
        nextPage: Int,
        kind: ReadingPlanKind,
        startDate: Date,
        today: Date,
        calendar: Calendar
    ) -> ClosedRange<Int>? {
        let first = max(1, nextPage)
        guard first <= pageCount else { return nil }
        let remaining = pageCount - first + 1
        let count: Int
        switch kind {
        case .days(let total):
            let elapsed = max(0, dayIndex(from: startDate, to: today, calendar: calendar))
            let daysLeft = max(1, total - elapsed)
            count = (remaining + daysLeft - 1) / daysLeft
        case .pace(let pagesPerDay):
            count = pagesPerDay
        }
        let last = min(pageCount, first + max(1, count) - 1)
        return first...last
    }

    /// The pages a day a fresh day plan asks for, rounded up: 21 for 30 days.
    static func pagesPerDay(forDays days: Int) -> Int {
        let total = max(1, days)
        return (pageCount + total - 1) / total
    }

    /// Pages read so far, 0...604.
    static func pagesRead(nextPage: Int) -> Int {
        min(pageCount, max(0, nextPage - 1))
    }

    /// Share of the Quran read so far, 0...1.
    static func fraction(nextPage: Int) -> Double {
        Double(pagesRead(nextPage: nextPage)) / Double(pageCount)
    }
}

/// The plan's words, kept apart so tests can check them.
enum ReadingPlanText {
    static let makePlan = "Make a reading plan"
    static let doneForToday = "Done for today"
    static let finished = "You finished the whole Quran"

    /// "pages 12 to 31", or "page 604" for a single page.
    static func pages(_ range: ClosedRange<Int>) -> String {
        if range.lowerBound == range.upperBound {
            return "page \(range.lowerBound)"
        }
        return "pages \(range.lowerBound) to \(range.upperBound)"
    }

    /// "Today: pages 12 to 31".
    static func todayLine(_ range: ClosedRange<Int>) -> String {
        "Today: \(pages(range))"
    }

    /// "1 page a day" or "5 pages a day".
    static func pagesPerDay(_ count: Int) -> String {
        count == 1 ? "1 page a day" : "\(count) pages a day"
    }

    /// The one line for the Learn tab.
    static func summary(plan: ReadingPlan?, today: Date, calendar: Calendar) -> String {
        guard let plan else { return makePlan }
        if plan.isFinished { return finished }
        if plan.isDone(on: today, calendar: calendar) { return doneForToday }
        guard let range = plan.portion(on: today, calendar: calendar) else { return finished }
        return todayLine(range)
    }
}

/// A saved reading plan.
struct ReadingPlan: Equatable, Sendable {
    var kind: ReadingPlanKind
    /// The day the plan (or its latest change) started.
    var startDate: Date
    /// The next page to read, 1...605; 605 means the whole Quran has been read.
    var nextPage: Int
    /// When "I read today's portion" was last tapped.
    var lastDoneDate: Date?

    var isFinished: Bool {
        nextPage > ReadingPlanMath.pageCount
    }

    var pagesRead: Int {
        ReadingPlanMath.pagesRead(nextPage: nextPage)
    }

    func portion(on today: Date, calendar: Calendar) -> ClosedRange<Int>? {
        ReadingPlanMath.todaysPortion(
            nextPage: nextPage,
            kind: kind,
            startDate: startDate,
            today: today,
            calendar: calendar
        )
    }

    func isDone(on today: Date, calendar: Calendar) -> Bool {
        guard let lastDoneDate else { return false }
        return calendar.isDate(lastDoneDate, inSameDayAs: today)
    }
}
