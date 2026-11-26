import SwiftUI

/// The single source of "now" for the app, injected through the environment.
struct AppClock {
    var now: () -> Date

    static let system = AppClock(now: { Date() })

    /// A clock frozen at the middle of `phase` for today's times at `place`, in the place's time zone.
    static func fixed(
        in phase: Prayer,
        at place: Place,
        service: PrayerTimesService,
        today: Date
    ) -> AppClock? {
        guard let day = service.prayerDay(for: place, on: today) else { return nil }
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
