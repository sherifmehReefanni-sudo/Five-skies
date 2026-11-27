import Foundation

/// A prayer whose time has just begun.
struct PrayerArrival: Equatable {
    let prayer: Prayer
    let time: Date
}

/// Tells the app when a prayer time arrives, so the recitation player can pause for prayer.
/// No polling: it works out the next prayer start, sleeps once until that instant, checks the
/// clock on waking, then sleeps until the one after. Off in fixed phase screenshot mode and in
/// the unit test host; tests that need it build it with `isEnabled: true`.
final class PrayerArrivalMonitor: ObservableObject {
    /// A start this long ago or less still counts as arriving now.
    static let arrivalWindow: TimeInterval = 2 * 60

    /// The latest prayer start that was signalled.
    @Published private(set) var lastArrival: PrayerArrival?

    /// Called on the main actor each time a prayer time arrives.
    var onArrival: (@MainActor (PrayerArrival) -> Void)?

    let isEnabled: Bool

    private let service: PrayerTimesService
    private let rules: () -> (method: PrayerCalculationMethod, asrRule: AsrRule)
    private let place: () -> Place
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - service: the base service; the user's method and Asr rule are applied on each schedule.
    ///   - rules: the user's current calculation method and Asr rule.
    ///   - place: the device place, or `Place.makkahFallback`.
    ///   - now: the app clock.
    ///   - isEnabled: false makes every method do nothing.
    ///   - sleep: waits the given number of seconds; tests pass a fake.
    init(
        service: PrayerTimesService,
        rules: @escaping () -> (method: PrayerCalculationMethod, asrRule: AsrRule),
        place: @escaping () -> Place,
        now: @escaping () -> Date,
        isEnabled: Bool,
        sleep: @escaping (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.service = service
        self.rules = rules
        self.place = place
        self.now = now
        self.isEnabled = isEnabled
        self.sleep = sleep
    }

    /// The app's monitor: reads the method and Asr rule from `settings` and the time from `clock`.
    convenience init(
        service: PrayerTimesService,
        settings: AppSettings,
        place: @escaping () -> Place,
        clock: AppClock,
        launch: LaunchOptions
    ) {
        self.init(
            service: service,
            rules: { (method: settings.calculationMethod, asrRule: settings.asrRule) },
            place: place,
            now: clock.now,
            isEnabled: launch.fixedPhase == nil && !launch.isUnitTestHost
        )
    }

    deinit {
        task?.cancel()
    }

    // MARK: - Pure logic

    /// The next prayer start strictly after `now`. After Isha this is tomorrow's Fajr.
    /// `tomorrow` is used only if `now` is already past the day's own next-day Fajr.
    static func nextArrival(after now: Date, day: PrayerDay, tomorrow: PrayerDay?) -> PrayerArrival {
        let upcoming = day.nextPrayer(after: now)
        if upcoming.time <= now, let tomorrow {
            let later = tomorrow.nextPrayer(after: now)
            return PrayerArrival(prayer: later.prayer, time: later.time)
        }
        return PrayerArrival(prayer: upcoming.prayer, time: upcoming.time)
    }

    /// True when `now` is at the start or no more than two minutes after it.
    /// A start further in the past (the device slept through it) never fires.
    static func shouldFire(arrival: PrayerArrival, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(arrival.time)
        return elapsed >= 0 && elapsed <= arrivalWindow
    }

    // MARK: - Lifecycle

    /// Starts watching. Does nothing if it is already running or disabled.
    @MainActor
    func start() {
        guard isEnabled, task == nil else { return }
        task = makeTask()
    }

    /// Stops watching and cancels the pending sleep.
    @MainActor
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Works out the next prayer again: call when the app becomes active, or when settings or
    /// the location change. Cancels the pending sleep and starts a new one.
    @MainActor
    func refresh() {
        guard isEnabled else { return }
        task?.cancel()
        task = makeTask()
    }

    /// Waits for the running watch to finish. Used by tests, whose fake sleep ends it.
    @MainActor
    func waitUntilStopped() async {
        if let running = task {
            await running.value
        }
    }

    // MARK: - Private

    @MainActor
    private func makeTask() -> Task<Void, Never> {
        let sleep = self.sleep
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let arrival = self?.upcomingArrival(), let wait = self?.seconds(until: arrival) else {
                    return
                }
                if wait > 0 {
                    do {
                        try await sleep(wait)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled, let monitor = self else { return }
                monitor.wake(for: arrival)
            }
        }
    }

    /// The next prayer start for the current place, method and Asr rule, or nil if none can be found.
    @MainActor
    private func upcomingArrival() -> PrayerArrival? {
        let current = now()
        let spot = place()
        let chosen = rules()
        let configured = service.applying(method: chosen.method, asrRule: chosen.asrRule)
        guard let day = configured.prayerDay(for: spot, on: current) else { return nil }
        var tomorrow: PrayerDay? = nil
        if current >= day.tomorrowFajr,
           let nextDate = spot.calendar.date(byAdding: .day, value: 1, to: current) {
            tomorrow = configured.prayerDay(for: spot, on: nextDate)
        }
        let arrival = Self.nextArrival(after: current, day: day, tomorrow: tomorrow)
        // Never loop on a time that is not ahead of the clock.
        guard arrival.time > current else { return nil }
        return arrival
    }

    @MainActor
    private func seconds(until arrival: PrayerArrival) -> TimeInterval {
        arrival.time.timeIntervalSince(now())
    }

    /// Fires if the clock is inside the arrival window. If the sleep ended early, the loop
    /// finds the same prayer again and sleeps the rest of the way.
    @MainActor
    private func wake(for arrival: PrayerArrival) {
        let current = now()
        guard current >= arrival.time else { return }
        guard Self.shouldFire(arrival: arrival, now: current), lastArrival != arrival else { return }
        lastArrival = arrival
        onArrival?(arrival)
    }
}
