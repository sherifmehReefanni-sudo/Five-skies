import SwiftUI

@main
struct FiveSkiesApp: App {
    @StateObject private var location: LocationProvider
    /// Tells the player when a prayer time arrives, for "Pause for prayer".
    @StateObject private var arrivals: PrayerArrivalMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var scheduler: NotificationScheduler
    /// Loads the bundled Quran text once, off the main thread, for the Quran tab.
    @StateObject private var quran = QuranStore()
    /// Quran Foundation translations, kept offline only through Content Sync.
    @StateObject private var translations: TranslationStore
    /// Decides when the signature shooting star plays on Today.
    @StateObject private var signatureStar = SignatureStarController()
    /// The one recitation player, shared by the Quran tab and the lock screen controls.
    @StateObject private var listenPlayer: ListenPlayer
    /// True until the first-run flow closes, so Today does not ask for location behind it.
    @State private var firstRunPending = OnboardingGate.live().shouldShow
    /// Lets any screen open the reader at an ayah and bring the Quran tab forward.
    @StateObject private var navigator = QuranNavigator()

    private let launch: LaunchOptions
    private let service: PrayerTimesService
    private let clock: AppClock

    init() {
        let launch = LaunchOptions()
        let service = PrayerTimesService()
        let settings = AppSettings()
        let location = LocationProvider()
        _location = StateObject(wrappedValue: location)
        let translationStore = TranslationStore.live()
        _translations = StateObject(wrappedValue: translationStore)
        let player = ListenPlayer.live()
        player.timingProvider = SurahTimingFactory.live()
        player.meaningProvider = TranslationMeaningProvider(store: translationStore)
        _listenPlayer = StateObject(wrappedValue: player)
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
        // Locals only: the autoclosure below must not capture self.
        let monitorClock = clock
        let monitor = PrayerArrivalMonitor(
            service: service,
            settings: settings,
            place: { location.coordinate.map { Place.device($0) } ?? Place.makkahFallback },
            clock: monitorClock,
            launch: launch
        )
        _arrivals = StateObject(wrappedValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $navigator.selectedTab) {
                TodayView(
                    location: location,
                    service: service,
                    requestsLocation: launch.requestsLocation && !firstRunPending
                )
                .id(firstRunPending)
                .tabArrival()
                .legibleTabBar()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)

                QuranTabView()
                    .tabArrival()
                    .legibleTabBar()
                    .tabItem { Label("Quran", systemImage: "book") }
                    .tag(AppTab.quran)

                LearnTabView()
                    .tabArrival()
                    .legibleTabBar()
                    .tabItem { Label("Learn", systemImage: "graduationcap") }
                    .tag(AppTab.learn)

                QiblaTabView()
                    .tabArrival()
                    .legibleTabBar()
                    .tabItem { Label("Qibla", systemImage: "safari") }
                    .tag(AppTab.qibla)

                MoreTabView()
                    .tabArrival()
                    .legibleTabBar()
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    .tag(AppTab.more)
            }
            .firstRunFlow(location: location) { firstRunPending = false }
            .whatsNewSheet()
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
            .modifier(SignatureStarLifecycle(controller: signatureStar))
            .modifier(ContinueListeningNote(player: listenPlayer))
            .modifier(PrayerPauseWiring(arrivals: arrivals, player: listenPlayer, settings: settings, location: location))
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
            .environmentObject(translations)
            .environmentObject(signatureStar)
            .environmentObject(listenPlayer)
            .environmentObject(navigator)
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

/// Notes each surah that starts playing for Today's continue card.
private struct ContinueListeningNote: ViewModifier {
    @ObservedObject var player: ListenPlayer
    @Environment(\.appClock) private var clock

    func body(content: Content) -> some View {
        content
            .onChange(of: player.item) { _, item in
                guard let item else { return }
                ContinueStore.shared.noteListening(
                    sura: item.chapter,
                    ayah: player.currentAyah,
                    reciterName: item.reciter.name,
                    at: clock.now()
                )
            }
    }
}

/// Connects prayer arrivals to the player and keeps the monitor's next wake-up current.
private struct PrayerPauseWiring: ViewModifier {
    @ObservedObject var arrivals: PrayerArrivalMonitor
    let player: ListenPlayer
    @ObservedObject var settings: AppSettings
    @ObservedObject var location: LocationProvider

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                arrivals.onArrival = { [weak player] arrival in
                    player?.prayerTimeArrived(name: arrival.prayer.displayName)
                }
                arrivals.start()
            }
            .onChange(of: settings.snapshot) { _, _ in arrivals.refresh() }
            .onChange(of: location.coordinate) { _, _ in arrivals.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    arrivals.refresh()
                }
            }
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
