import SwiftUI

/// The Qibla tab: living sky, a compass whose needle points toward the Kaaba, and turn guidance.
struct QiblaTabView: View {
    // TodayView receives its LocationProvider from FiveSkiesApp rather than the environment,
    // so this tab owns its own instance, started the same way.
    @StateObject private var location: LocationProvider
    @StateObject private var headingProvider: HeadingProvider

    private let launch: LaunchOptions
    private let qiblaLaunch: QiblaLaunchOptions

    init() {
        let launch = LaunchOptions()
        let qiblaLaunch = QiblaLaunchOptions()
        self.launch = launch
        self.qiblaLaunch = qiblaLaunch
        _location = StateObject(wrappedValue: LocationProvider())
        _headingProvider = StateObject(wrappedValue: HeadingProvider(fixedHeading: qiblaLaunch.fixedHeading))
    }

    var body: some View {
        QiblaScreen(
            place: place,
            fixedPhase: launch.fixedPhase,
            heading: headingProvider.heading,
            pillOpensSettings: requestsLocation && location.isDenied,
            requestLocation: requestLocation
        )
            .onAppear {
                if requestsLocation {
                    location.start()
                }
                headingProvider.start()
            }
            .onDisappear {
                headingProvider.stop()
            }
    }

    /// Where the tab is for. The `-FSFixedCoordinate` override uses the device time zone;
    /// with no location the labelled Makkah fallback is used, in Makkah's own time zone.
    private var place: Place {
        if let fixed = qiblaLaunch.fixedCoordinate {
            return Place.device(fixed)
        }
        if launch.fixedPhase != nil {
            return Place.makkahFallback
        }
        if let coordinate = location.coordinate {
            return Place.device(coordinate)
        }
        return Place.makkahFallback
    }

    private func requestLocation() {
        guard requestsLocation else { return }
        location.requestAgain()
    }

    private var requestsLocation: Bool {
        qiblaLaunch.fixedCoordinate == nil && launch.requestsLocation
    }
}

private struct QiblaScreen: View {
    let place: Place
    let fixedPhase: Prayer?
    let heading: Double?
    let pillOpensSettings: Bool
    let requestLocation: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var bearingSize: CGFloat = 60
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    private var resolved: Coordinate {
        place.coordinate
    }

    /// The Qibla direction is undefined at the Kaaba itself, so the fallback shows no number.
    private var bearing: Double? {
        resolved == .makkah ? nil : QiblaBearing.degrees(from: resolved)
    }

    private var guidance: QiblaGuidance.State {
        QiblaGuidance.state(bearing: bearing, heading: heading)
    }

    var body: some View {
        ZStack {
            QiblaSky(place: place, fixedPhase: fixedPhase)
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    QiblaCompass(bearing: bearing, heading: heading, guidance: guidance)
                        .padding(.top, 24)
                    bearingLabel
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                    guidancePill
                        .padding(.top, 16)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .foregroundStyle(.white)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Qibla")
                .font(.system(size: titleSize, weight: .heavy))
                .kerning(-1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("qiblaTitle")
            Spacer(minLength: 8)
            LocationPill(
                text: locationText,
                opensSettings: pillOpensSettings,
                identifier: "qiblaLocationPill",
                request: requestLocation
            )
        }
    }

    /// Same rules as the Today pill.
    private var locationText: String {
        place.isFallback ? LocationPillText.fallback : LocationPillText.current
    }

    @ViewBuilder
    private var bearingLabel: some View {
        if let bearing = bearing {
            Text(QiblaGuidance.bearingText(bearing))
                .font(.system(size: bearingSize, weight: .black))
                .kerning(-2)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 17, y: 10)
                .accessibilityIdentifier("qiblaBearing")
        } else {
            Text("Set your location")
                .font(.largeTitle.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 17, y: 10)
                .accessibilityIdentifier("qiblaBearing")
        }
    }

    private var guidancePill: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(guidance == .aligned ? QiblaPalette.mint : QiblaPalette.gold)
                .accessibilityHidden(true)
            Text(guidance.text)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color(hex: 0x120B1F, opacity: 0.55)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }

    private var iconName: String {
        switch guidance {
        case .needsLocation: return "location.slash"
        case .noCompass: return "safari"
        case .aligned: return "checkmark.circle.fill"
        case .turnRight: return "arrow.right"
        case .turnLeft: return "arrow.left"
        }
    }
}

enum QiblaPalette {
    static let gold = Color(hex: 0xFBC56A)
    static let goldLight = Color(hex: 0xFFF1C9)
    static let mint = Color(hex: 0x8FF0C8)
    static let ink = Color(hex: 0x120B1F)
}

/// The app sky for the current prayer period at the place, or the forced phase.
/// The sun and moon are hidden so nothing bright sits behind the compass and bearing.
private struct QiblaSky: View {
    let place: Place
    let fixedPhase: Prayer?

    @Environment(\.appClock) private var clock
    private let service = PrayerTimesService()

    var body: some View {
        TimelineView(.periodic(from: clock.now(), by: 60)) { _ in
            SkyView(phase: phase(at: clock.now()), showsCelestial: false)
        }
    }

    private func phase(at now: Date) -> Prayer {
        if let fixed = fixedPhase {
            return fixed
        }
        return service.prayerDay(for: place, on: now)?.skyPhase(at: now) ?? .isha
    }
}
