import SwiftUI

/// The single source of "now" for the app, injected through the environment.
struct AppClock {
    var now: () -> Date

    static let system = AppClock(now: { Date() })

    /// A clock frozen at the middle of `phase` for today's times at `coordinate`.
    static func fixed(
        in phase: Prayer,
        at coordinate: Coordinate,
        service: PrayerTimesService,
        today: Date
    ) -> AppClock? {
        guard let day = service.prayerDay(at: coordinate, on: today) else { return nil }
        let instant = day.midpoint(of: phase)
        return AppClock(now: { instant })
    }
}

private struct AppClockKey: EnvironmentKey {
    static let defaultValue = AppClock.system
}

extension EnvironmentValues {
    var appClock: AppClock {
        get { self[AppClockKey.self] }
        set { self[AppClockKey.self] = newValue }
    }
}
