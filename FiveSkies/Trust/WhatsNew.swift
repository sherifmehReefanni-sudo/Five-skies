import SwiftUI

/// The "What's new" sheet: shown once per new marketing version.
enum WhatsNew {
    static let lastSeenKey = "trust.whatsNew.lastSeenVersion"

    struct Item: Identifiable, Equatable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    static let items: [Item] = [
        Item(
            id: "polish",
            symbol: "sparkles",
            title: "A fresh look",
            detail: "A shooting star crosses the sky when you open the app, when the prayer time changes and when you mark a prayer. Smoother screens and clearer cards."
        ),
        Item(
            id: "dayView",
            symbol: "clock",
            title: "Day view",
            detail: "Tap the date on Today to see each prayer's window, sunrise, Duha, the last third of the night, Suhur and Iftar."
        ),
        Item(
            id: "tracker",
            symbol: "checkmark.circle",
            title: "Tracker 2",
            detail: "A week strip, a 7-day trend, streaks that start from your first tracked day, monthly history, and pauses for travel or illness."
        ),
        Item(
            id: "alerts",
            symbol: "bell",
            title: "Alerts and night alarm",
            detail: "Choose off, silent or a short sound for each prayer, a reminder before a window ends, and a night alarm for the last third of the night or Fajr."
        ),
        Item(
            id: "goals",
            symbol: "target",
            title: "Goals",
            detail: "Personal goals that forgive gaps and go at your own pace."
        )
    ]

    /// True when there is a version and it differs from the last one the user saw.
    static func shouldShow(currentVersion: String?, lastSeen: String?) -> Bool {
        guard let current = currentVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !current.isEmpty else {
            return false
        }
        return current != lastSeen
    }

    /// The marketing version (`CFBundleShortVersionString`) of the app.
    static func currentVersion(bundle: Bundle = .main) -> String? {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Decides whether to show the sheet now and records the version as seen, so it shows once.
    /// Recorded without showing: a fresh install with no saved app data (a new user has nothing
    /// to compare against), and a launch where the first-run flow shows (one screen at a time).
    static func evaluate(
        currentVersion: String?,
        defaults: UserDefaults = .standard,
        firstRunFlowShows: Bool = false
    ) -> Bool {
        let lastSeen = defaults.string(forKey: lastSeenKey)
        guard shouldShow(currentVersion: currentVersion, lastSeen: lastSeen),
              let currentVersion else {
            return false
        }
        defaults.set(currentVersion, forKey: lastSeenKey)
        if firstRunFlowShows {
            return false
        }
        if lastSeen == nil && !hasAppData(in: defaults) {
            return false
        }
        return true
    }

    /// Whether any setting or progress the backup would include is saved.
    static func hasAppData(in defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { BackupService.isIncluded($0) }
    }
}

/// The list of recent changes, with a close button.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MoreScreenTitle(text: "What's new", identifier: "whatsNewTitle")
                    .padding(.top, 24)

                ForEach(WhatsNew.items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(MorePalette.gold)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                            Text(item.detail)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MorePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .moreGlass(.dark, cornerRadius: 24)
                    .accessibilityElement(children: .combine)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(MorePalette.goldGradient)
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("whatsNewDone")
                .padding(.top, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.more)
    }
}

/// Shows "What's new" once per new marketing version. Never in fixed phase screenshot mode
/// or the unit test host.
private struct WhatsNewSheetModifier: ViewModifier {
    @State private var isPresented = false
    @State private var hasChecked = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasChecked else { return }
                hasChecked = true
                let launch = LaunchOptions()
                guard launch.fixedPhase == nil, !launch.isUnitTestHost else { return }
                isPresented = WhatsNew.evaluate(
                    currentVersion: WhatsNew.currentVersion(),
                    firstRunFlowShows: OnboardingGate.live().shouldShow
                )
            }
            .sheet(isPresented: $isPresented) {
                WhatsNewView()
            }
    }
}

extension View {
    /// Apply once, at the app root.
    func whatsNewSheet() -> some View {
        modifier(WhatsNewSheetModifier())
    }
}
