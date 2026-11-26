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
        QiblaScreen(coordinate: coordinate, fixedPhase: launch.fixedPhase, heading: headingProvider.heading)
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

    /// The coordinate to use, or nil for the labelled Makkah fallback.
    private var coordinate: Coordinate? {
        if let fixed = qiblaLaunch.fixedCoordinate {
            return fixed
        }
        if launch.fixedPhase != nil {
            return nil
        }
        return location.coordinate
    }

    private var requestsLocation: Bool {
        qiblaLaunch.fixedCoordinate == nil && launch.requestsLocation
    }
}

private struct QiblaScreen: View {
    let coordinate: Coordinate?
    let fixedPhase: Prayer?
    let heading: Double?

    @ScaledMetric(relativeTo: .largeTitle) private var bearingSize: CGFloat = 60
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    private var resolved: Coordinate {
        coordinate ?? .makkah
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
            QiblaSky(coordinate: resolved, fixedPhase: fixedPhase)
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
            Text(locationText)
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .accessibilityIdentifier("qiblaLocationPill")
        }
    }

    /// Same rules as the Today pill.
    private var locationText: String {
        coordinate == nil ? "Makkah (set your location)" : "Current location"
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

/// The app sky for the current prayer period at the coordinate, or the forced phase.
private struct QiblaSky: View {
    let coordinate: Coordinate
    let fixedPhase: Prayer?

    @Environment(\.appClock) private var clock
    private let service = PrayerTimesService()

    var body: some View {
        TimelineView(.periodic(from: clock.now(), by: 60)) { _ in
            SkyView(phase: phase(at: clock.now()))
        }
    }

    private func phase(at now: Date) -> Prayer {
        if let fixed = fixedPhase {
            return fixed
        }
        return service.prayerDay(at: coordinate, on: now)?.skyPhase(at: now) ?? .isha
    }
}
