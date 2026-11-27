import SwiftUI
import WidgetKit

@main
struct FiveSkiesWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        TodayPrayersWidget()
        PrayerProgressWidget()
        LockScreenPrayerWidget()
    }
}

/// "Next prayer" on its sky (systemSmall).
struct NextPrayerWidget: Widget {
    let kind = "NextPrayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimelineProvider()) { entry in
            SmallPrayerWidgetView(entry: entry, drawsBackground: false)
                .containerBackground(for: .widget) {
                    SmallPrayerWidgetView.background(for: entry)
                }
        }
        .configurationDisplayName("Next prayer")
        .description("The next prayer, its time and a live countdown.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// "Today's prayers" (systemMedium).
struct TodayPrayersWidget: Widget {
    let kind = "TodayPrayersWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimelineProvider()) { entry in
            MediumPrayerWidgetView(entry: entry, drawsBackground: false)
                .containerBackground(for: .widget) {
                    MediumPrayerWidgetView.background
                }
        }
        .configurationDisplayName("Today's prayers")
        .description("The next prayer and all five times for today.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// "Prayers and progress" (systemLarge).
struct PrayerProgressWidget: Widget {
    let kind = "PrayerProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: PrayerTimelineProvider(progressStep: PrayerWidgetTimeline.progressStep)
        ) { entry in
            LargePrayerWidgetView(entry: entry, drawsBackground: false)
                .containerBackground(for: .widget) {
                    LargePrayerWidgetView.background
                }
        }
        .configurationDisplayName("Prayers and progress")
        .description("All five times and how far along the day is toward the next prayer.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Lock screen circle, rectangle and inline line.
struct LockScreenPrayerWidget: Widget {
    let kind = "LockScreenPrayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: PrayerTimelineProvider(progressStep: PrayerWidgetTimeline.progressStep)
        ) { entry in
            LockScreenPrayerEntryView(entry: entry)
        }
        .configurationDisplayName("Next prayer")
        .description("The next prayer on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockScreenPrayerEntryView: View {
    let entry: PrayerWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularPrayerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    AccessoryWidgetBackground()
                }
        case .accessoryRectangular:
            RectangularPrayerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        default:
            InlinePrayerWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
    }
}
