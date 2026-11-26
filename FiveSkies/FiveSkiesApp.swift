import SwiftUI

@main
struct FiveSkiesApp: App {
    @StateObject private var location = LocationProvider()

    private let launch: LaunchOptions
    private let service: PrayerTimesService
    private let clock: AppClock

    init() {
        let launch = LaunchOptions()
        let service = PrayerTimesService()
        self.launch = launch
        self.service = service
        if let phase = launch.fixedPhase,
           let fixed = AppClock.fixed(
               in: phase,
               at: .makkah,
               service: service,
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

                ComingSoonView(title: "Qibla")
                    .tabItem { Label("Qibla", systemImage: "safari") }

                ComingSoonView(title: "More")
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
            }
            .tint(Color(hex: 0xFFD27A))
            .preferredColorScheme(.dark)
            .environment(\.appClock, clock)
        }
    }
}
