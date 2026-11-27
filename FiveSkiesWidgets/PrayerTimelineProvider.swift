import Foundation
import WidgetKit

extension PrayerWidgetEntry: TimelineEntry {}

/// Computes prayer times for the shared place and settings and emits one entry at each prayer
/// boundary (plus the next midnight). With `progressStep` set it also emits entries between
/// boundaries so progress rings and bars move along. The countdown text updates on its own.
struct PrayerTimelineProvider: TimelineProvider {
    var progressStep: TimeInterval?

    func placeholder(in context: Context) -> PrayerWidgetEntry {
        entry(at: Date(), config: .fallback)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerWidgetEntry) -> Void) {
        let config = context.isPreview ? SharedPrayerConfig.fallback : SharedPrayerConfigStore.shared.loadOrFallback()
        completion(entry(at: Date(), config: config))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerWidgetEntry>) -> Void) {
        let now = Date()
        let config = SharedPrayerConfigStore.shared.loadOrFallback()
        let entries = PrayerWidgetTimeline.entries(config: config, now: now, progressStep: progressStep)
        if entries.isEmpty {
            // No prayer times could be computed here: show placeholder times and try again in an hour.
            let fallback = PrayerWidgetEntry.placeholder(at: now, timeZone: config.place.timeZone)
            completion(Timeline(entries: [fallback], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, config: SharedPrayerConfig) -> PrayerWidgetEntry {
        PrayerWidgetTimeline.entry(at: date, config: config)
            ?? PrayerWidgetEntry.placeholder(at: date, timeZone: config.place.timeZone)
    }
}
