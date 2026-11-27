import SwiftUI

@main
struct FiveSkiesApp: App {
    @StateObject private var location = LocationProvider()
    @StateObject private var settings: AppSettings
    @StateObject private var scheduler: NotificationScheduler
    /// Loads the bundled Quran text once, off the main thread, for the Quran tab.
    @StateObject private var quran = QuranStore()

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
               at: Place.makkahFallback,
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
                .legibleTabBar()
                .tabItem { Label("Today", systemImage: "sun.max") }

                QuranTabView()
                    .legibleTabBar()
                    .tabItem { Label("Quran", systemImage: "book") }

                ComingSoonView(title: "Listen")
                    .legibleTabBar()
                    .tabItem { Label("Listen", systemImage: "headphones") }

                QiblaTabView()
                    .legibleTabBar()
                    .tabItem { Label("Qibla", systemImage: "safari") }

                MoreTabView()
                    .legibleTabBar()
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
            .modifier(WidgetGalleryOverride(
                isActive: launch.fixedPhase != nil && WidgetGalleryLaunch.isRequested()
            ))
            .modifier(WidgetConfigSync(settings: settings, location: location, isEnabled: launch.requestsLocation))
            .modifier(NotificationRefresh(
                settings: settings,
                scheduler: scheduler,
                location: location,
                service: service
            ))
            .modifier(MotionEnvironment(
                isFixedPhase: launch.fixedPhase != nil,
                forcesAnimation: MotionPolicy.forcesAnimation()
            ))
            .tint(Color(hex: 0xFFD27A))
            .preferredColorScheme(.dark)
            .environment(\.appClock, clock)
            .environmentObject(settings)
            .environmentObject(scheduler)
            .environmentObject(quran)
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
            place: location.coordinate.map { Place.device($0) } ?? Place.makkahFallback,
            preferences: settings.alertPreferences,
            now: clock.now()
        )
    }
}

extension View {
    /// A dark, always visible tab bar so its icons stay legible over every sky.
    /// Applied to the content inside each tab, where these modifiers take effect.
    func legibleTabBar() -> some View {
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(Color(hex: 0x120B1F, opacity: 0.55), for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }
}
