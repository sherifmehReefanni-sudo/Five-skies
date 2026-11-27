import SwiftUI

/// The `-FSWidgetGallery` testing hook. It only takes effect together with `-FSFixedPhase`,
/// so the gallery always runs on the fixed clock with the Makkah fallback and no prompts.
enum WidgetGalleryLaunch {
    static let argument = "-FSWidgetGallery"

    static func isRequested(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
    }
}

/// Shows the widget gallery instead of the app's content when `isActive` is true.
struct WidgetGalleryOverride: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            WidgetGalleryView()
        } else {
            content
        }
    }
}

/// Debug only: every widget drawn at its real point size on a wallpaper-like gradient,
/// because widgets themselves cannot be screenshotted in CI.
struct WidgetGalleryView: View {
    @Environment(\.appClock) private var clock
    @EnvironmentObject private var settings: AppSettings

    private static let cornerRadius: CGFloat = 22

    var body: some View {
        let config = SharedPrayerConfig(
            place: .makkahFallback,
            calculationMethod: settings.calculationMethod,
            asrRule: settings.asrRule
        )
        let now = clock.now()
        let entry = PrayerWidgetTimeline.entry(at: now, config: config)
            ?? PrayerWidgetEntry.placeholder(at: now, timeZone: config.place.timeZone)

        ZStack {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(hex: 0x1B2A6B), location: 0),
                    Gradient.Stop(color: Color(hex: 0x5B4A8F), location: 0.55),
                    Gradient.Stop(color: Color(hex: 0xC66B7A), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Widget gallery")
                        .font(.system(size: 15, weight: .heavy))
                        .accessibilityIdentifier("widgetGallery")

                    caption("Lock screen")
                    InlinePrayerWidgetView(entry: entry)
                        .font(.system(size: 13, weight: .semibold))

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            caption("Small")
                            SmallPrayerWidgetView(entry: entry, countdown: .frozen)
                                .frame(width: 170, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            caption("Circular and rectangular")
                            CircularPrayerWidgetView(entry: entry)
                                .frame(width: 76, height: 76)
                                .background(Circle().fill(Color.white.opacity(0.14)))
                            RectangularPrayerWidgetView(entry: entry, countdown: .frozen)
                                .padding(.horizontal, 10)
                                .frame(width: 172, height: 76)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.14))
                                )
                        }
                    }

                    caption("Medium")
                    MediumPrayerWidgetView(entry: entry, countdown: .frozen)
                        .frame(width: 364, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))

                    caption("Large")
                    LargePrayerWidgetView(entry: entry, countdown: .frozen)
                        .frame(width: 364, height: 382)
                        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.85))
    }
}
