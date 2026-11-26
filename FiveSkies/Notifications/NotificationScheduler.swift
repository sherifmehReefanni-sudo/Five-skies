import Foundation
import UserNotifications

/// Schedules the prayer notifications with UNUserNotificationCenter.
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
    }

    private var lastContext: Context?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    convenience init(launch: LaunchOptions) {
        self.init(isEnabled: launch.fixedPhase == nil && !launch.isUnitTestHost)
    }

    /// Asks for alert and sound permission if any prayer has alerts on. Called from the settings screen.
    func requestAuthorizationIfNeeded(preferences: AlertPreferences) {
        guard isEnabled else { return }
        guard preferences.wantsAnyAlert else {
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

    /// Replaces this app's pending prayer notifications with a fresh plan for today and tomorrow.
    /// Days and day keys are worked out in the place's own time zone.
    func reschedule(service base: PrayerTimesService, place: Place, preferences: AlertPreferences, now: Date) {
        guard isEnabled else { return }
        lastContext = Context(service: base, place: place, preferences: preferences)

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
        let plan = NotificationPlan.make(days: days, preferences: preferences, now: now, calendar: calendar)
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
            now: Date()
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
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: item.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }
}
