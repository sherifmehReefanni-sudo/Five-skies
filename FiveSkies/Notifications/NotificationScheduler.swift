import Foundation
import UserNotifications

/// Schedules the prayer notifications with UNUserNotificationCenter, and the night alarm
/// with AlarmKit on iOS 26 and later (see NightAlarmKit.swift).
/// When disabled (fixed phase UI tests or the unit test host) every method does nothing,
/// so tests never touch the notification center or see a permission prompt.
final class NotificationScheduler: ObservableObject {
    /// True when the user has turned notifications off for the app in iPhone Settings.
    @Published private(set) var isDenied = false

    let isEnabled: Bool

    private struct Context {
        let service: PrayerTimesService
        let place: Place
        var preferences: AlertPreferences
        let isPrivate: Bool
    }

    private var lastContext: Context?
    /// Counts reschedules so a slower, older refresh never overwrites a newer one.
    private var generation = 0
    /// The latest refresh, so refreshes run one after another.
    private var alarmTask: Task<Void, Never>?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    convenience init(launch: LaunchOptions) {
        self.init(isEnabled: launch.fixedPhase == nil && !launch.isUnitTestHost)
    }

    /// Asks for alert and sound permission if any prayer has alerts on or the night alarm is on.
    /// Called from the settings screen.
    func requestAuthorizationIfNeeded(preferences: AlertPreferences) {
        guard isEnabled else { return }
        guard preferences.needsNotificationPermission else {
            refreshAuthorizationStatus()
            return
        }
        lastContext?.preferences = preferences
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                self.refreshAuthorizationStatus()
                self.rescheduleLast()
            }
        }
    }

    /// Called when the user turns the night alarm on. On iOS 26 and later asks for AlarmKit
    /// permission; then asks for notification permission, which is the fallback.
    func nightAlarmTurnedOn(preferences: AlertPreferences) {
        guard isEnabled else { return }
        lastContext?.preferences = preferences
        Task { @MainActor in
            _ = await NightAlarmBridge.requestAuthorization()
            self.requestAuthorizationIfNeeded(preferences: preferences)
        }
    }

    /// Updates `isDenied` from the current notification settings.
    func refreshAuthorizationStatus() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async {
                self.setDenied(denied)
            }
        }
    }

    /// Replaces this app's pending notifications with a fresh plan for today and tomorrow,
    /// and refreshes the night alarm. Days and day keys are worked out in the place's own time zone.
    /// `isPrivate` (plan N6, `AppSettings.privateReminders`) gives every alert the private wording.
    func reschedule(
        service base: PrayerTimesService,
        place: Place,
        preferences: AlertPreferences,
        now: Date,
        isPrivate: Bool = false
    ) {
        guard isEnabled else { return }
        lastContext = Context(service: base, place: place, preferences: preferences, isPrivate: isPrivate)

        let service = base.inTimeZone(place.timeZone)
        let coordinate = place.coordinate
        let calendar = place.calendar
        var days: [PrayerDay] = []
        if let today = service.prayerDay(at: coordinate, on: now) {
            days.append(today)
        }
        if let nextDate = calendar.date(byAdding: .day, value: 1, to: now),
           let tomorrow = service.prayerDay(at: coordinate, on: nextDate) {
            days.append(tomorrow)
        }

        var schedules: [DaySchedule] = []
        if preferences.endReminderMinutes > 0 {
            schedules = (0...1).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: now)
                    .flatMap { base.daySchedule(for: place, on: $0) }
            }
        }

        var nights: [PlannedNightAlarm] = []
        let nightSettings = preferences.nightAlarm
        if nightSettings.isEnabled {
            // Yesterday's night can still be ahead in the small hours; a week covers any choice of days.
            let nightSchedules: [DaySchedule] = (-1...7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: now)
                    .flatMap { base.daySchedule(for: place, on: $0) }
            }
            nights = NightAlarmPlan.upcoming(schedules: nightSchedules, settings: nightSettings, now: now, calendar: calendar)
        }

        // Fixed copies for the task below; captured vars are not allowed in concurrent code.
        let plannedDays = days
        let plannedSchedules = schedules
        let plannedNights = nights

        generation += 1
        let current = generation
        let previous = alarmTask
        alarmTask = Task { @MainActor in
            // One refresh at a time, and only the newest one runs.
            await previous?.value
            guard current == self.generation else { return }
            let usesAlarmKit = await NightAlarmBridge.sync(
                plannedNights,
                enabled: nightSettings.isEnabled,
                isPrivate: isPrivate
            )
            guard current == self.generation else { return }
            let plan = NotificationPlan.full(
                days: plannedDays,
                schedules: plannedSchedules,
                preferences: preferences,
                nightAlarms: usesAlarmKit ? [] : plannedNights,
                now: now,
                calendar: calendar,
                isPrivate: isPrivate
            )
            self.apply(plan)
        }
    }

    /// Adds `plan` to the notification center and removes our pending requests that are not in it.
    private func apply(_ plan: [PlannedNotification]) {
        let requests = plan.map(Self.request(for:))
        let wanted = Set(plan.map { $0.id })

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let allowed = status == .authorized || status == .provisional || status == .ephemeral
            DispatchQueue.main.async {
                self.setDenied(status == .denied)
            }
            center.getPendingNotificationRequests { pending in
                // Requests added with an id that is already pending replace it,
                // so only ids that are no longer in the plan need removing.
                let stale = pending
                    .map { $0.identifier }
                    .filter { NotificationPlan.isOwned($0) && (!allowed || !wanted.contains($0)) }
                if !stale.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: stale)
                }
                guard allowed else { return }
                for request in requests {
                    center.add(request, withCompletionHandler: nil)
                }
            }
        }
    }

    private func rescheduleLast() {
        guard let context = lastContext else { return }
        reschedule(
            service: context.service,
            place: context.place,
            preferences: context.preferences,
            now: Date(),
            isPrivate: context.isPrivate
        )
    }

    private func setDenied(_ denied: Bool) {
        if isDenied != denied {
            isDenied = denied
        }
    }

    private static func request(for item: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = item.hasSound ? UNNotificationSound.default : nil
        if item.isTimeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: item.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }
}
