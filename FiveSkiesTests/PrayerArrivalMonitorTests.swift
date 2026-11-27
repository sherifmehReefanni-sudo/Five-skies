import XCTest
@testable import FiveSkies

final class PrayerArrivalMonitorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(hours: Double) -> Date {
        base.addingTimeInterval(hours * 3600)
    }

    private var day: PrayerDay {
        PrayerDay(
            fajr: at(hours: 5),
            sunrise: at(hours: 6.5),
            dhuhr: at(hours: 12),
            asr: at(hours: 15.5),
            maghrib: at(hours: 18),
            isha: at(hours: 19.5),
            tomorrowFajr: at(hours: 29)
        )
    }

    // MARK: - nextArrival

    func testNextArrivalBeforeFajrIsTodaysFajr() {
        let arrival = PrayerArrivalMonitor.nextArrival(after: at(hours: 2), day: day, tomorrow: nil)
        XCTAssertEqual(arrival, PrayerArrival(prayer: .fajr, time: at(hours: 5)))
    }

    func testNextArrivalBetweenPrayers() {
        XCTAssertEqual(
            PrayerArrivalMonitor.nextArrival(after: at(hours: 9), day: day, tomorrow: nil),
            PrayerArrival(prayer: .dhuhr, time: at(hours: 12))
        )
        XCTAssertEqual(
            PrayerArrivalMonitor.nextArrival(after: at(hours: 16), day: day, tomorrow: nil),
            PrayerArrival(prayer: .maghrib, time: at(hours: 18))
        )
    }

    func testNextArrivalAtAPrayerStartIsTheFollowingPrayer() {
        let arrival = PrayerArrivalMonitor.nextArrival(after: at(hours: 12), day: day, tomorrow: nil)
        XCTAssertEqual(arrival, PrayerArrival(prayer: .asr, time: at(hours: 15.5)))
    }

    func testNextArrivalAfterIshaRollsToTomorrowsFajr() {
        let arrival = PrayerArrivalMonitor.nextArrival(after: at(hours: 22), day: day, tomorrow: nil)
        XCTAssertEqual(arrival, PrayerArrival(prayer: .fajr, time: at(hours: 29)))
    }

    func testNextArrivalUsesTomorrowOnlyWhenPastTheNextDayFajr() {
        let tomorrow = PrayerDay(
            fajr: at(hours: 29),
            sunrise: at(hours: 30.5),
            dhuhr: at(hours: 36),
            asr: at(hours: 39.5),
            maghrib: at(hours: 42),
            isha: at(hours: 43.5),
            tomorrowFajr: at(hours: 53)
        )
        XCTAssertEqual(
            PrayerArrivalMonitor.nextArrival(after: at(hours: 22), day: day, tomorrow: tomorrow),
            PrayerArrival(prayer: .fajr, time: at(hours: 29))
        )
        XCTAssertEqual(
            PrayerArrivalMonitor.nextArrival(after: at(hours: 30), day: day, tomorrow: tomorrow),
            PrayerArrival(prayer: .dhuhr, time: at(hours: 36))
        )
    }

    // MARK: - shouldFire

    func testFiresInsideTheTwoMinuteWindow() {
        let arrival = PrayerArrival(prayer: .maghrib, time: at(hours: 18))
        XCTAssertTrue(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time))
        XCTAssertTrue(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time.addingTimeInterval(1)))
        XCTAssertTrue(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time.addingTimeInterval(120)))
    }

    func testDoesNotFireForAStaleTime() {
        let arrival = PrayerArrival(prayer: .maghrib, time: at(hours: 18))
        XCTAssertFalse(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time.addingTimeInterval(121)))
        XCTAssertFalse(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time.addingTimeInterval(3 * 3600)))
    }

    func testDoesNotFireBeforeTheStart() {
        let arrival = PrayerArrival(prayer: .maghrib, time: at(hours: 18))
        XCTAssertFalse(PrayerArrivalMonitor.shouldFire(arrival: arrival, now: arrival.time.addingTimeInterval(-1)))
    }

    // MARK: - The watch loop, driven by a fake clock and a fake sleep

    private final class FakeClock {
        var now: Date
        var sleeps: [TimeInterval] = []

        init(now: Date) {
            self.now = now
        }
    }

    private let place = Place.makkahFallback
    private let service = PrayerTimesService()

    private func makkahDay() throws -> PrayerDay {
        let date = try XCTUnwrap(place.calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 9)))
        let configured = service.applying(method: AppSettings.defaultCalculationMethod, asrRule: AppSettings.defaultAsrRule)
        return try XCTUnwrap(configured.prayerDay(for: place, on: date))
    }

    /// A monitor whose first sleep moves the clock forward by the wait plus `lateBy`,
    /// and whose second sleep throws so the loop ends.
    private func makeMonitor(clock: FakeClock, lateBy: TimeInterval = 0, isEnabled: Bool = true) -> PrayerArrivalMonitor {
        PrayerArrivalMonitor(
            service: service,
            rules: { (method: AppSettings.defaultCalculationMethod, asrRule: AppSettings.defaultAsrRule) },
            place: { [place] in place },
            now: { clock.now },
            isEnabled: isEnabled,
            sleep: { seconds in
                clock.sleeps.append(seconds)
                if clock.sleeps.count > 1 {
                    throw CancellationError()
                }
                clock.now = clock.now.addingTimeInterval(seconds + lateBy)
            }
        )
    }

    @MainActor
    func testSleepsUntilTheNextPrayerAndFiresOnce() async throws {
        let day = try makkahDay()
        let clock = FakeClock(now: day.dhuhr.addingTimeInterval(-90))
        let monitor = makeMonitor(clock: clock)
        var fired: [PrayerArrival] = []
        monitor.onArrival = { fired.append($0) }

        monitor.start()
        await monitor.waitUntilStopped()

        let expected = PrayerArrival(prayer: .dhuhr, time: day.dhuhr)
        XCTAssertEqual(fired, [expected])
        XCTAssertEqual(monitor.lastArrival, expected)
        XCTAssertEqual(clock.sleeps.count, 2)
        XCTAssertEqual(clock.sleeps[0], 90, accuracy: 0.001)
        // The second sleep is the wait for Asr.
        XCTAssertEqual(clock.sleeps[1], day.asr.timeIntervalSince(day.dhuhr), accuracy: 0.001)
    }

    @MainActor
    func testWakingLongAfterTheStartDoesNotFire() async throws {
        let day = try makkahDay()
        let clock = FakeClock(now: day.maghrib.addingTimeInterval(-60))
        let monitor = makeMonitor(clock: clock, lateBy: 10 * 60)
        var fired: [PrayerArrival] = []
        monitor.onArrival = { fired.append($0) }

        monitor.start()
        await monitor.waitUntilStopped()

        XCTAssertTrue(fired.isEmpty)
        XCTAssertNil(monitor.lastArrival)
        XCTAssertEqual(clock.sleeps.count, 2)
    }

    @MainActor
    func testDisabledMonitorNeverSleepsOrFires() async throws {
        let day = try makkahDay()
        let clock = FakeClock(now: day.asr.addingTimeInterval(-30))
        let monitor = makeMonitor(clock: clock, isEnabled: false)
        var fired: [PrayerArrival] = []
        monitor.onArrival = { fired.append($0) }

        monitor.start()
        monitor.refresh()
        await monitor.waitUntilStopped()

        XCTAssertTrue(clock.sleeps.isEmpty)
        XCTAssertTrue(fired.isEmpty)
    }

    func testTheAppMonitorIsOffInTheUnitTestHost() {
        let monitor = PrayerArrivalMonitor(
            service: service,
            settings: AppSettings(defaults: UserDefaults(suiteName: "PrayerArrivalMonitorTests") ?? .standard),
            place: { Place.makkahFallback },
            clock: .system,
            launch: LaunchOptions()
        )
        XCTAssertFalse(monitor.isEnabled)
    }
}
