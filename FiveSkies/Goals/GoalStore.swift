import Foundation

/// Saves personal goals in UserDefaults as JSON, oldest first.
struct GoalStore {
    static let storageKey = "goals.items"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [PersonalGoal] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PersonalGoal].self, from: data)
        else {
            return []
        }
        return decoded
    }

    func save(_ goals: [PersonalGoal]) {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func add(_ goal: PersonalGoal) {
        save(load() + [goal])
    }

    func update(_ goal: PersonalGoal) {
        var all = load()
        guard let index = all.firstIndex(where: { $0.id == goal.id }) else { return }
        all[index] = goal
        save(all)
    }

    func remove(id: UUID) {
        save(load().filter { $0.id != id })
    }
}

/// Saves the daily dhikr totals from the Tasbih in UserDefaults.
/// Keeps the last `keptDays` days only.
struct DhikrLogStore {
    static let totalsKey = "dhikr.totalsByDay"
    static let dailyGoalKey = "dhikr.dailyGoal"
    static let dailyGoalChoices = [0, 100, 300, 500, 1000]
    static let keptDays = 60

    private let defaults: UserDefaults
    let counter: GoalCounter

    init(defaults: UserDefaults = .standard, counter: GoalCounter = GoalCounter()) {
        self.defaults = defaults
        self.counter = counter
    }

    func load() -> DhikrTotals {
        guard let data = defaults.data(forKey: Self.totalsKey),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return DhikrTotals()
        }
        return DhikrTotals(byDay: decoded)
    }

    /// Adds `amount` to the total for the local day of `date` and returns the new totals.
    @discardableResult
    func add(_ amount: Int, at date: Date) -> DhikrTotals {
        var totals = load()
        totals.add(amount, on: counter.dayKey(for: date))
        if let oldest = counter.lastDays(Self.keptDays, endingOn: date).first {
            totals.prune(before: counter.dayKey(for: oldest))
        }
        if let data = try? JSONEncoder().encode(totals.byDay) {
            defaults.set(data, forKey: Self.totalsKey)
        }
        return totals
    }
}
