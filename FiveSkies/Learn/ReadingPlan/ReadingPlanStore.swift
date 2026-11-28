import Foundation

/// The saved reading plan. Every key starts with "readingPlan." so the whole plan can be
/// included in the iCloud backup by that one prefix.
@MainActor
final class ReadingPlanStore: ObservableObject {
    static let keyPrefix = "readingPlan."
    static let kindKey = "readingPlan.kind"
    static let startDateKey = "readingPlan.startDate"
    static let nextPageKey = "readingPlan.nextPage"
    static let lastDoneDateKey = "readingPlan.lastDoneDate"

    /// With `-FSFixedPhase`, shows a 30 day plan started 3 days ago at page 61, for screenshots.
    static let sampleArgument = "-FSPlanSample"
    /// The throwaway suite used in screenshot mode, so UI tests never touch the real plan.
    static let screenshotSuiteName = "app.fiveskies.readingPlan.screenshots"

    static let shared = ReadingPlanStore.live()

    @Published private(set) var plan: ReadingPlan?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        plan = Self.read(from: defaults)
    }

    /// The real store in the app. In screenshot mode (`-FSFixedPhase`) a throwaway suite,
    /// emptied at launch, holding the sample plan when `-FSPlanSample` is also given.
    static func live(processInfo: ProcessInfo = .processInfo, now: Date = Date(), calendar: Calendar = .current) -> ReadingPlanStore {
        guard LaunchOptions(processInfo: processInfo).fixedPhase != nil,
              let suite = UserDefaults(suiteName: screenshotSuiteName)
        else {
            return ReadingPlanStore()
        }
        suite.removePersistentDomain(forName: screenshotSuiteName)
        let store = ReadingPlanStore(defaults: suite)
        if processInfo.arguments.contains(sampleArgument) {
            store.save(sample(now: now, calendar: calendar))
        }
        return store
    }

    /// A 30 day plan that started 3 days ago, with pages 1 to 60 read.
    static func sample(now: Date, calendar: Calendar) -> ReadingPlan {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        return ReadingPlan(kind: .days(30), startDate: start, nextPage: 61, lastDoneDate: nil)
    }

    // MARK: - Reading

    func portion(today: Date, calendar: Calendar = .current) -> ClosedRange<Int>? {
        plan?.portion(on: today, calendar: calendar)
    }

    func isDoneToday(_ today: Date, calendar: Calendar = .current) -> Bool {
        plan?.isDone(on: today, calendar: calendar) ?? false
    }

    /// Reads the saved plan again, for example after a restore from backup.
    func reload() {
        let stored = Self.read(from: defaults)
        if stored != plan {
            plan = stored
        }
    }

    // MARK: - Changes

    /// Starts a new plan at page 1.
    func start(_ kind: ReadingPlanKind, today: Date) {
        save(ReadingPlan(kind: kind, startDate: today, nextPage: 1, lastDoneDate: nil))
    }

    /// Switches to another plan and keeps the pages read. The rest is spread from today.
    func change(to kind: ReadingPlanKind, today: Date) {
        guard var current = plan else {
            start(kind, today: today)
            return
        }
        current.kind = kind
        current.startDate = today
        save(current)
    }

    /// Moves past today's pages. Once a day; returns false when already done today or finished.
    @discardableResult
    func markTodayDone(today: Date, calendar: Calendar = .current) -> Bool {
        guard var current = plan,
              !current.isDone(on: today, calendar: calendar),
              let range = current.portion(on: today, calendar: calendar)
        else { return false }
        current.nextPage = min(ReadingPlanMath.finishedPage, range.upperBound + 1)
        current.lastDoneDate = today
        save(current)
        return true
    }

    /// Reads the whole Quran again with the same kind of plan, from today.
    func startAgain(today: Date) {
        let kind = plan?.kind ?? .days(30)
        start(kind, today: today)
    }

    /// Removes the plan.
    func remove() {
        for key in [Self.kindKey, Self.startDateKey, Self.nextPageKey, Self.lastDoneDateKey] {
            defaults.removeObject(forKey: key)
        }
        plan = nil
    }

    // MARK: - Storage

    private func save(_ newPlan: ReadingPlan) {
        defaults.set(newPlan.kind.storageValue, forKey: Self.kindKey)
        defaults.set(newPlan.startDate.timeIntervalSince1970, forKey: Self.startDateKey)
        defaults.set(newPlan.nextPage, forKey: Self.nextPageKey)
        if let done = newPlan.lastDoneDate {
            defaults.set(done.timeIntervalSince1970, forKey: Self.lastDoneDateKey)
        } else {
            defaults.removeObject(forKey: Self.lastDoneDateKey)
        }
        plan = newPlan
    }

    private static func read(from defaults: UserDefaults) -> ReadingPlan? {
        guard let raw = defaults.string(forKey: kindKey),
              let kind = ReadingPlanKind(storageValue: raw),
              defaults.object(forKey: startDateKey) != nil
        else { return nil }
        let start = Date(timeIntervalSince1970: defaults.double(forKey: startDateKey))
        let storedPage = defaults.object(forKey: nextPageKey) == nil ? 1 : defaults.integer(forKey: nextPageKey)
        let nextPage = min(ReadingPlanMath.finishedPage, max(1, storedPage))
        let lastDone = defaults.object(forKey: lastDoneDateKey) == nil
            ? nil
            : Date(timeIntervalSince1970: defaults.double(forKey: lastDoneDateKey))
        return ReadingPlan(kind: kind, startDate: start, nextPage: nextPage, lastDoneDate: lastDone)
    }
}
