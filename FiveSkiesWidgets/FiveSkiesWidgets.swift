import SwiftUI
import WidgetKit

@main
struct FiveSkiesWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        TodayPrayersWidget()
        PrayerProgressWidget()
        LockScreenPrayerWidget()
        TodayTimesLockWidget()
    }
}

/// "Next prayer" on its sky (systemSmall). iOS 17 also shows this size in StandBy, where the
/// system may drop the container background; the text stays legible on black.
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
        .description("The next prayer and when each prayer starts and ends today.")
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
        .description("Each prayer's start and end, and how far along you are toward the next one.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Lock screen circle (progress toward the next prayer), rectangle (next prayer, time and a
/// live countdown) and inline line.
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
        .description("The next prayer and a live countdown on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// Lock screen rectangle listing all five times, the current one marked. Entries at each
/// prayer time and at sunrise move the mark on time.
struct TodayTimesLockWidget: Widget {
    let kind = "TodayTimesLockWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerTimelineProvider()) { entry in
            TodayTimesRectangularView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Today's times")
        .description("All five prayer times on your Lock Screen, the current one marked.")
        .supportedFamilies([.accessoryRectangular])
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
