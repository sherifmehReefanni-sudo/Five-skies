import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

/// Hands the night alarm to AlarmKit on iOS 26 and later.
/// On earlier versions, or when AlarmKit is not authorized, every call reports false
/// and the scheduler falls back to a time-sensitive notification.
enum NightAlarmBridge {
    /// Asks for AlarmKit permission if it has not been asked yet. Call only when the user turns
    /// the night alarm on. Returns true when AlarmKit may schedule alarms.
    @MainActor
    static func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await NightAlarmKitScheduler.requestAuthorization()
        }
        #endif
        return false
    }

    /// Makes this app's AlarmKit alarms match `alarms`. When `enabled` is false, cancels ours.
    /// Returns true when AlarmKit now holds the night alarm, so no notification is needed.
    /// `isPrivate` (plan N6) titles the alarm "Alarm" instead of "Night alarm".
    @MainActor
    static func sync(_ alarms: [PlannedNightAlarm], enabled: Bool, isPrivate: Bool = false) async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await NightAlarmKitScheduler.sync(alarms, enabled: enabled, isPrivate: isPrivate)
        }
        #endif
        return false
    }
}

#if canImport(AlarmKit)
/// No extra data; AlarmKit requires a metadata type.
@available(iOS 26.0, *)
struct NightAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
enum NightAlarmKitScheduler {
    /// Our alarm ids share this prefix; the rest of the id is the ring day as digits,
    /// so the same night always gets the same id.
    static let idPrefix = "5E7A1A40-0000-4000-8000-"

    /// A stable id for an alarm, from its "night-yyyy-MM-dd" plan id.
    static func alarmID(for alarm: PlannedNightAlarm) -> UUID? {
        let digits = alarm.id.filter { $0.isNumber }
        guard digits.count == 8 else { return nil }
        return UUID(uuidString: idPrefix + "0000" + digits)
    }

    static func isOurs(_ id: UUID) -> Bool {
        id.uuidString.uppercased().hasPrefix(idPrefix)
    }

    @MainActor
    static func requestAuthorization() async -> Bool {
        let manager = AlarmManager.shared
        let state = manager.authorizationState
        if state == .authorized { return true }
        if state == .denied { return false }
        do {
            return try await manager.requestAuthorization() == .authorized
        } catch {
            return false
        }
    }

    @MainActor
    static func sync(_ alarms: [PlannedNightAlarm], enabled: Bool, isPrivate: Bool) async -> Bool {
        let manager = AlarmManager.shared
        let state = manager.authorizationState
        // Never asked: nothing of ours can exist, and asking happens only from settings.
        if state == .notDetermined { return false }

        let existing = ((try? manager.alarms) ?? []).filter { isOurs($0.id) }
        guard enabled, state == .authorized else {
            for alarm in existing {
                try? manager.cancel(id: alarm.id)
            }
            return false
        }

        // Leave an alarm that is ringing right now alone; replace the rest.
        var ringing: Set<UUID> = []
        for alarm in existing {
            if case .alerting = alarm.state {
                ringing.insert(alarm.id)
            } else {
                try? manager.cancel(id: alarm.id)
            }
        }

        for item in alarms {
            guard let id = alarmID(for: item), !ringing.contains(id) else { continue }
            do {
                _ = try await manager.schedule(id: id, configuration: configuration(for: item, isPrivate: isPrivate))
            } catch {
                // Fall back to notifications rather than leave a half-made set.
                let current = ((try? manager.alarms) ?? []).filter { isOurs($0.id) }
                for alarm in current where !ringing.contains(alarm.id) {
                    try? manager.cancel(id: alarm.id)
                }
                return false
            }
        }
        return true
    }

    private static func configuration(for item: PlannedNightAlarm, isPrivate: Bool) -> AlarmManager.AlarmConfiguration<NightAlarmMetadata> {
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        // Literal titles, as AlarmKit takes a LocalizedStringResource. Private mode says only "Alarm".
        let alert: AlarmPresentation.Alert
        if isPrivate {
            alert = AlarmPresentation.Alert(title: "Alarm", stopButton: stop)
        } else {
            alert = AlarmPresentation.Alert(title: "Night alarm", stopButton: stop)
        }
        let attributes = AlarmAttributes<NightAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: NightAlarmMetadata(),
            tintColor: Color(hex: 0xFFD27A)
        )
        return AlarmManager.AlarmConfiguration<NightAlarmMetadata>.alarm(
            schedule: .fixed(item.fireDate),
            attributes: attributes
        )
    }
}
#endif
