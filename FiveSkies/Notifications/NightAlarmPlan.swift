import Foundation

/// One night alarm to schedule, either with AlarmKit or as a notification.
struct PlannedNightAlarm: Equatable {
    /// "night-yyyy-MM-dd", the calendar day the alarm rings on.
    let id: String
    let fireDate: Date
}

/// Works out when the night alarm rings. Pure: no system calls, no clock.
enum NightAlarmPlan {
    static let idPrefix = "night-"
    /// Only the next one or two alarms are scheduled; each reschedule refreshes them.
    static let maxScheduled = 2

    /// The alarm time for the night that follows `schedule`'s day:
    /// the last third of that night, or the next morning's Fajr, moved by `offsetMinutes`
    /// (negative is before).
    static func fireDate(for schedule: DaySchedule, anchor: NightAlarmAnchor, offsetMinutes: Int) -> Date {
        let base: Date
        switch anchor {
        case .lastThirdOfNight: base = schedule.lastThirdOfNight
        case .fajr: base = schedule.day.tomorrowFajr
        }
        return base.addingTimeInterval(Double(offsetMinutes) * 60)
    }

    /// The next alarms after `now`, earliest first, at most `limit`.
    /// `schedules` should start with yesterday's, because the night after yesterday can still
    /// be ahead in the small hours. Nights whose ring day is not in `settings.weekdays` are skipped.
    static func upcoming(
        schedules: [DaySchedule],
        settings: NightAlarmSettings,
        now: Date,
        calendar: Calendar,
        limit: Int = NightAlarmPlan.maxScheduled
    ) -> [PlannedNightAlarm] {
        guard settings.isEnabled, limit > 0 else { return [] }
        var seen: Set<String> = []
        var alarms: [PlannedNightAlarm] = []
        for schedule in schedules {
            let fire = fireDate(for: schedule, anchor: settings.anchor, offsetMinutes: settings.offsetMinutes)
            guard fire > now else { continue }
            let weekday = calendar.component(.weekday, from: fire)
            guard settings.weekdays.contains(weekday) else { continue }
            let id = idPrefix + NotificationPlan.dayKey(for: fire, calendar: calendar)
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            alarms.append(PlannedNightAlarm(id: id, fireDate: fire))
        }
        return Array(alarms.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
