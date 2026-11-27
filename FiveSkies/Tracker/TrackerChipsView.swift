import Combine
import SwiftUI

/// Small glass capsules for Today: prayers marked today and the current streak.
/// Reads the stores itself. Refreshes when `now` changes and when stored marks change,
/// with no timer of its own. Not interactive unless `onTap` is given.
struct TrackerChipsView: View {
    let now: Date
    let onTap: (() -> Void)?

    @State private var summary = TrackerChipsSummary(markedToday: 0, streak: 0, isPausedToday: false)

    init(now: Date, onTap: (() -> Void)? = nil) {
        self.now = now
        self.onTap = onTap
    }

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trackerChips")
            .onAppear(perform: refresh)
            .onChange(of: now) { _, _ in
                refresh()
            }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: UserDefaults.didChangeNotification)
                    .receive(on: RunLoop.main)
            ) { _ in
                refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let onTap {
            Button(action: onTap) {
                chips
            }
            .buttonStyle(PressScaleButtonStyle())
        } else {
            chips
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip(
                symbol: summary.markedToday >= Prayer.allCases.count ? "checkmark.circle.fill" : "circle.dashed",
                text: "\(summary.markedToday) of \(Prayer.allCases.count) today"
            )
            if summary.isPausedToday {
                chip(symbol: "pause.circle", text: "Paused", tint: TrackerPalette.pause)
            } else if summary.streak > 0 {
                chip(symbol: "sparkles", text: "Streak \(summary.streak)")
            }
        }
        .fixedSize()
    }

    private func chip(symbol: String, text: String, tint: Color = MorePalette.mint) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Capsule().fill(Color(hex: 0x120B1F, opacity: 0.55)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func refresh() {
        let next = TrackerHistory.load().chipsSummary(today: now)
        if next != summary {
            summary = next
        }
    }
}
