import Foundation

/// One local notification to schedule.
struct PlannedNotification: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let hasSound: Bool
    /// Asks for time-sensitive delivery. Without the entitlement iOS shows it as a normal alert.
    var isTimeSensitive: Bool = false
}

/// Works out which notifications to schedule. Pure: no system calls, no clock.
enum NotificationPlan {
    static let prayerPrefix = "prayer-"
    static let reminderPrefix = "reminder-"
    static let endPrefix = "end-"
    static let nightPrefix = NightAlarmPlan.idPrefix
    /// iOS keeps at most 64 pending local notifications per app and drops the rest.
    static let pendingLimit = 64

    /// Private mode (plan N6): the same alerts at the same times, with no prayer name and no
    /// religious wording, for people who have not told family or coworkers.
    static let privateTitle = "Reminder"
    static let privateBody = "You set this reminder."
    static let privateNightAlarmTitle = "Alarm"
    static let nightAlarmTitle = "Night alarm"

    /// Whether an identifier belongs to a notification this app schedules.
    static func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(prayerPrefix)
            || identifier.hasPrefix(reminderPrefix)
            || identifier.hasPrefix(endPrefix)
            || identifier.hasPrefix(nightPrefix)
    }

    /// Everything to schedule: prayer times and reminders for `days`, "ends soon" reminders for
    /// `schedules`, and the night alarms given (empty when AlarmKit handles them).
    /// Sorted by fire date and capped at `limit`, dropping the furthest first.
    static func full(
        days: [PrayerDay],
        schedules: [DaySchedule],
        preferences: AlertPreferences,
        nightAlarms: [PlannedNightAlarm],
        now: Date,
        calendar: Calendar,
        limit: Int = NotificationPlan.pendingLimit,
        isPrivate: Bool = false
    ) -> [PlannedNotification] {
        var all = make(days: days, preferences: preferences, now: now, calendar: calendar, isPrivate: isPrivate)
        let taken = Set(all.map { $0.id })
        let extra = endReminders(schedules: schedules, preferences: preferences, now: now, calendar: calendar, isPrivate: isPrivate)
            + nightAlarmNotifications(nightAlarms.filter { $0.fireDate > now }, isPrivate: isPrivate)
        all.append(contentsOf: extra.filter { !taken.contains($0.id) })
        return capped(all, limit: limit)
    }

    /// The earliest `limit` items, sorted by fire date.
    static func capped(_ items: [PlannedNotification], limit: Int = NotificationPlan.pendingLimit) -> [PlannedNotification] {
        let sorted = items.sorted { lhs, rhs in
            lhs.fireDate == rhs.fireDate ? lhs.id < rhs.id : lhs.fireDate < rhs.fireDate
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// "Asr ends in 15 minutes", for each prayer with alerts on, that many minutes before its
    /// window ends. Windows come from `DaySchedule.window(of:ishaEnd:)`. Skipped when the window
    /// is shorter than the reminder or the time has passed. `isPrivate` gives the private wording.
    static func endReminders(
        schedules: [DaySchedule],
        preferences: AlertPreferences,
        now: Date,
        calendar: Calendar,
        isPrivate: Bool = false
    ) -> [PlannedNotification] {
        let minutes = preferences.endReminderMinutes
        guard minutes > 0 else { return [] }
        var planned: [PlannedNotification] = []
        var seen: Set<String> = []
        for schedule in schedules {
            let key = dayKey(for: schedule.day.fajr, calendar: calendar)
            for prayer in Prayer.allCases {
                let mode = preferences.mode(for: prayer)
                guard mode != .off else { continue }
                let window = schedule.window(of: prayer, ishaEnd: preferences.ishaEnd)
                let fire = window.end.addingTimeInterval(-Double(minutes) * 60)
                let id = endPrefix + key + "-" + prayer.rawValue
                guard fire > now, fire > window.start, !seen.contains(id) else { continue }
                seen.insert(id)
                let name = prayer.displayName
                planned.append(PlannedNotification(
                    id: id,
                    fireDate: fire,
                    title: isPrivate ? privateTitle : "\(name) ends in \(minutes) minutes",
                    body: isPrivate ? privateBody : "There is still time to pray.",
                    hasSound: mode == .sound
                ))
            }
        }
        return planned.sorted { $0.fireDate < $1.fireDate }
    }

    /// The night alarm as a time-sensitive notification with the default sound,
    /// for iOS versions without AlarmKit. `isPrivate` titles it "Alarm".
    static func nightAlarmNotifications(_ alarms: [PlannedNightAlarm], isPrivate: Bool = false) -> [PlannedNotification] {
        alarms.map { alarm in
            PlannedNotification(
                id: alarm.id,
                fireDate: alarm.fireDate,
                title: isPrivate ? privateNightAlarmTitle : nightAlarmTitle,
                body: "This is the wake time you set.",
                hasSound: true,
                isTimeSensitive: true
            )
        }
    }

    /// Notifications for every prayer in `days` that is still after `now`, plus reminders.
    /// Prayers whose mode is off are skipped. The day in each id is the calendar day of
    /// that `PrayerDay`'s Fajr in `calendar`, so ids stay stable across reschedules.
    /// With `isPrivate` every title is "Reminder" and no body names a prayer; times, ids and
    /// sounds are the same.
    static func make(
        days: [PrayerDay],
        preferences: AlertPreferences,
        now: Date,
        calendar: Calendar,
        isPrivate: Bool = false
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
                            title: isPrivate ? privateTitle : "\(name) in \(minutes) minutes",
                            body: isPrivate ? privateBody : "Prepare for prayer.",
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
                        title: isPrivate ? privateTitle : name,
                        body: isPrivate ? privateBody : "It is time for \(name).",
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
