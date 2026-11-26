import SwiftUI

@main
struct FiveSkiesApp: App {
    @StateObject private var location = LocationProvider()
    @StateObject private var settings: AppSettings
    @StateObject private var scheduler: NotificationScheduler

    private let launch: LaunchOptions
    private let service: PrayerTimesService
    private let clock: AppClock

    init() {
        let launch = LaunchOptions()
        let service = PrayerTimesService()
        let settings = AppSettings()
        self.launch = launch
        self.service = service
        _settings = StateObject(wrappedValue: settings)
        _scheduler = StateObject(wrappedValue: NotificationScheduler(launch: launch))
        if let phase = launch.fixedPhase,
           let fixed = AppClock.fixed(
               in: phase,
               at: .makkah,
               service: service.applying(method: settings.calculationMethod, asrRule: settings.asrRule),
               today: AppClock.system.now()
           ) {
            clock = fixed
        } else {
            clock = .system
        }
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView(
                    location: location,
                    service: service,
                    requestsLocation: launch.requestsLocation
                )
                .tabItem { Label("Today", systemImage: "sun.max") }

                ComingSoonView(title: "Quran")
                    .tabItem { Label("Quran", systemImage: "book") }

                ComingSoonView(title: "Listen")
                    .tabItem { Label("Listen", systemImage: "headphones") }

                QiblaTabView()
                    .tabItem { Label("Qibla", systemImage: "safari") }

                MoreTabView()
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
            .modifier(NotificationRefresh(
                settings: settings,
                scheduler: scheduler,
                location: location,
                service: service
            ))
            .tint(Color(hex: 0xFFD27A))
            .preferredColorScheme(.dark)
            .environment(\.appClock, clock)
            .environmentObject(settings)
            .environmentObject(scheduler)
        }
    }
}

/// Reschedules prayer notifications when settings change and when the app becomes active.
private struct NotificationRefresh: ViewModifier {
    @ObservedObject var settings: AppSettings
    @ObservedObject var scheduler: NotificationScheduler
    @ObservedObject var location: LocationProvider
    let service: PrayerTimesService

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appClock) private var clock

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.snapshot) { _, _ in
                reschedule()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reschedule()
                }
            }
    }

    private func reschedule() {
        scheduler.reschedule(
            service: service.applying(method: settings.calculationMethod, asrRule: settings.asrRule),
            coordinate: location.coordinate ?? .makkah,
            preferences: settings.alertPreferences,
            now: clock.now()
        )
    }
}
