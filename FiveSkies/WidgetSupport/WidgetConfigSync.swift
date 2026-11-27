import CoreLocation
import SwiftUI
import WidgetKit

/// Writes the place, calculation method and Asr rule to the App Group for the widgets whenever
/// they change, then asks WidgetKit to rebuild the timelines. Off in testing modes.
struct WidgetConfigSync: ViewModifier {
    @ObservedObject var settings: AppSettings
    @ObservedObject var location: LocationProvider
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { sync() }
            .onChange(of: settings.calculationMethod) { _, _ in sync() }
            .onChange(of: settings.asrRule) { _, _ in sync() }
            .onChange(of: location.coordinate) { _, _ in sync() }
            .onChange(of: location.authorizationStatus) { _, _ in sync() }
    }

    private func sync() {
        guard isEnabled else { return }
        let store = SharedPrayerConfigStore.shared
        let place: Place
        if let coordinate = location.coordinate {
            place = .device(coordinate)
        } else if location.isAwaitingFix, let stored = store.load() {
            // Keep the last known place while a fresh fix is on its way.
            place = stored.place
        } else {
            place = .makkahFallback
        }
        let config = SharedPrayerConfig(
            place: place,
            calculationMethod: settings.calculationMethod,
            asrRule: settings.asrRule
        )
        if store.save(config) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
