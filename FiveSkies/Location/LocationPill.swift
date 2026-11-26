import SwiftUI
import UIKit

/// The words on the location pill, shared by the Today and Qibla tabs.
enum LocationPillText {
    static let locating = "Locating\u{2026}"
    static let fallback = "Makkah \u{00B7} Set location"
    static let current = "Current location"
}

/// The capsule in the top row that says where the times are for.
/// Tapping it opens the app's page in iPhone Settings when location permission was refused,
/// and otherwise runs `request`, which asks for permission or tries for a fresh fix.
struct LocationPill: View {
    let text: String
    let opensSettings: Bool
    let identifier: String
    let request: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if opensSettings {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } else {
                request()
            }
        } label: {
            Text(text)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(opensSettings ? "Opens iPhone Settings to allow location" : "Uses your location"))
        .accessibilityIdentifier(identifier)
    }
}
