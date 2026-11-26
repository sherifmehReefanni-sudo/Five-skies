import Foundation

/// One local notification to schedule.
struct PlannedNotification: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let hasSound: Bool
}

/// Works out which notifications to schedule. Pure: no system calls, no clock.
enum NotificationPlan {
    static let prayerPrefix = "prayer-"
    static let reminderPrefix = "reminder-"

    /// Whether an identifier belongs to a notification this app schedules.
    static func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(prayerPrefix) || identifier.hasPrefix(reminderPrefix)
    }

    /// Notifications for every prayer in `days` that is still after `now`, plus reminders.
    /// Prayers whose mode is off are skipped. The day in each id is the calendar day of
    /// that `PrayerDay`'s Fajr in `calendar`, so ids stay stable across reschedules.
    static func make(
        days: [PrayerDay],
        preferences: AlertPreferences,
        now: Date,
        calendar: Calendar
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        var seen: Set<String> = []
        let minutes = preferences.reminderMinutesBefore

        for day in days {
            let key = dayKey(for: day.fajr, calendar: calendar)
            for prayer in Prayer.allCases {
                let mode = preferences.mode(for: prayer)
                guard mode != .off else { continue }
                let time = day.time(of: prayer)
                let hasSound = mode == .sound
                let name = prayer.displayName

                if minutes > 0 {
                    let fire = time.addingTimeInterval(-Double(minutes) * 60)
                    let id = reminderPrefix + key + "-" + prayer.rawValue
                    if fire > now, !seen.contains(id) {
                        seen.insert(id)
                        planned.append(PlannedNotification(
                            id: id,
                            fireDate: fire,
                            title: "\(name) in \(minutes) minutes",
                            body: "Prepare for prayer.",
                            hasSound: hasSound
                        ))
                    }
                }

                let id = prayerPrefix + key + "-" + prayer.rawValue
                if time > now, !seen.contains(id) {
                    seen.insert(id)
                    planned.append(PlannedNotification(
                        id: id,
                        fireDate: time,
                        title: name,
                        body: "It is time for \(name).",
                        hasSound: hasSound
                    ))
                }
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// "yyyy-MM-dd" for `date` in `calendar`.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
