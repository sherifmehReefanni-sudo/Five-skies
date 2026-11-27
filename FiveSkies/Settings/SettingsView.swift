import SwiftUI
import UIKit

/// The "Adhan and alerts" screen: per prayer alerts, reminders, the night alarm, and calculation settings.
/// Reads AppSettings and NotificationScheduler from the environment.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var scheduler: NotificationScheduler
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init() {}

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x050B24), location: 0),
                    .init(color: Color(hex: 0x141E55), location: 0.45),
                    .init(color: Color(hex: 0x3A2A6A), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 12)

                    if scheduler.isDenied {
                        permissionCard
                            .padding(.top, 20)
                    }

                    sectionTitle("Prayer alerts")
                    SettingsCard {
                        ForEach(Prayer.allCases) { prayer in
                            alertRow(for: prayer)
                            if prayer != Prayer.allCases.last {
                                SettingsDivider()
                            }
                        }
                    }

                    Group {
                        footnote("Silent shows a banner with no sound. Sound adds a short alert tone.")

                        sectionTitle("Reminders")
                        SettingsCard {
                            menuRow(
                                "Before prayer starts",
                                accessibilityName: "Reminder before prayer",
                                selection: $settings.reminderMinutesBefore,
                                options: AppSettings.reminderOptions,
                                label: Self.reminderLabel
                            )
                            SettingsDivider()
                            menuRow(
                                "Before prayer time ends",
                                accessibilityName: "Reminder before prayer time ends",
                                selection: $settings.endReminderMinutes,
                                options: AppSettings.endReminderOptions,
                                label: Self.reminderLabel
                            )
                        }
                        footnote("Reminders come for prayers with alerts on, with the same sound choice.")
                    }

                    Group {
                        sectionTitle("Night alarm")
                        SettingsCard {
                            HStack(spacing: 12) {
                                Text("Night alarm")
                                    .font(.subheadline.weight(.bold))
                                Spacer(minLength: 8)
                                Toggle("Night alarm", isOn: $settings.nightAlarmEnabled)
                                    .labelsHidden()
                                    .tint(Color(hex: 0xFBC56A))
                                    .accessibilityIdentifier("nightAlarmToggle")
                            }
                            .frame(minHeight: 50)

                            if settings.nightAlarmEnabled {
                                SettingsDivider()
                                HStack(spacing: 12) {
                                    Text("Wake for")
                                        .font(.subheadline.weight(.bold))
                                    Spacer(minLength: 8)
                                    Picker("Wake for", selection: $settings.nightAlarmAnchor) {
                                        ForEach(NightAlarmAnchor.allCases) { anchor in
                                            Text(anchor.displayName).tag(anchor)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .tint(Color(hex: 0xFFE0A3))
                                }
                                .frame(minHeight: 50)
                                SettingsDivider()
                                menuRow(
                                    "When",
                                    accessibilityName: "Night alarm time",
                                    selection: $settings.nightAlarmOffsetMinutes,
                                    options: NightAlarmSettings.offsetOptions,
                                    label: NightAlarmSettings.offsetLabel
                                )
                                SettingsDivider()
                                weekdayRow
                            }
                        }
                        footnote("On iOS 26 this uses a real alarm. On earlier versions it is a notification and follows your Focus settings.")
                    }

                    sectionTitle("Calculation")
                    SettingsCard {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calculation method")
                                .font(.subheadline.weight(.bold))
                                .padding(.top, 10)
                            Picker("Calculation method", selection: $settings.calculationMethod) {
                                ForEach(PrayerCalculationMethod.allCases) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(Color(hex: 0xFFE0A3))
                            .frame(minHeight: 44)
                        }
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Asr time")
                                .font(.subheadline.weight(.bold))
                                .padding(.top, 10)
                            Picker("Asr time", selection: $settings.asrRule) {
                                ForEach(AsrRule.allCases) { rule in
                                    Text(rule.displayName).tag(rule)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .tint(Color(hex: 0xFFE0A3))
                            .frame(minHeight: 44)
                        }
                    }

                    Text("On iPhone the lock screen plays a short alert. Full adhan audio is coming later.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear {
            scheduler.requestAuthorizationIfNeeded(preferences: settings.alertPreferences)
        }
        .onChange(of: settings.alertModes) { _, _ in
            scheduler.requestAuthorizationIfNeeded(preferences: settings.alertPreferences)
        }
        .onChange(of: settings.nightAlarmEnabled) { _, isOn in
            if isOn {
                scheduler.nightAlarmTurnedOn(preferences: settings.alertPreferences)
            }
        }
    }

    /// A row with a bold title and a menu picker on the right.
    private func menuRow(
        _ title: String,
        accessibilityName: String,
        selection: Binding<Int>,
        options: [Int],
        label: @escaping (Int) -> String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Picker(accessibilityName, selection: selection) {
                ForEach(options, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Color(hex: 0xFFE0A3))
        }
        .frame(minHeight: 50)
    }

    /// Seven day chips in the order of the user's calendar. At least one stays on.
    private var weekdayRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rings on")
                .font(.subheadline.weight(.bold))
            HStack(spacing: 6) {
                ForEach(Self.orderedWeekdays, id: \.self) { weekday in
                    weekdayChip(weekday)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func weekdayChip(_ weekday: Int) -> some View {
        let isOn = settings.nightAlarmWeekdays.contains(weekday)
        return Button {
            var days = settings.nightAlarmWeekdays
            if isOn {
                guard days.count > 1 else { return }
                days.remove(weekday)
            } else {
                days.insert(weekday)
            }
            settings.nightAlarmWeekdays = days
        } label: {
            Text(Self.shortWeekdayName(weekday))
                .font(.caption.weight(.heavy))
                .foregroundStyle(isOn ? Color(hex: 0x120B1F) : .white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    Capsule().fill(isOn ? Color(hex: 0xFBC56A) : Color.white.opacity(0.1))
                )
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.24), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.fullWeekdayName(weekday))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Calendar weekday numbers starting from the user's first day of the week.
    private static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private static func shortWeekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }

    private static func fullWeekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.84))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, 8)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Text("Adhan and alerts")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var permissionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Alerts are turned off for Five Skies in iPhone Settings. Turn on notifications there to get prayer alerts.")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text("Open iPhone Settings")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color(hex: 0x120B1F))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Color(hex: 0xFBC56A)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.heavy))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.84))
            .padding(.leading, 4)
            .padding(.top, 24)
            .padding(.bottom, 8)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }

    private func alertRow(for prayer: Prayer) -> some View {
        HStack(spacing: 12) {
            Text(prayer.displayName)
                .font(.subheadline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Picker("\(prayer.displayName) alert", selection: alertBinding(for: prayer)) {
                ForEach(AlertMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 196)
        }
        .frame(minHeight: 50)
    }

    private func alertBinding(for prayer: Prayer) -> Binding<AlertMode> {
        Binding(
            get: { settings.alertMode(for: prayer) },
            set: { settings.setAlertMode($0, for: prayer) }
        )
    }

    private static func reminderLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Off" : "\(minutes) min"
    }
}

/// A rounded glass card matching the mockup.
private struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
    }
}
