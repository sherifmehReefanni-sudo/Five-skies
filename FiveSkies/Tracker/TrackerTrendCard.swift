import SwiftUI

/// Prayers marked on each of the last seven days, as simple bars from 0 to 5.
/// Days before the user started are left blank; paused days get a soft pause mark.
struct TrackerTrendCard: View {
    let days: [TrackerDay]

    private static let barHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days")
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityIdentifier("trendSummary")
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    column(day)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
    }

    private var summaryText: String {
        let total = days
            .filter { $0.status.phase == .active }
            .reduce(0) { $0 + $1.status.count }
        return total == 1 ? "1 prayer marked" : "\(total) prayers marked"
    }

    private func column(_ day: TrackerDay) -> some View {
        let status = day.status
        let total = Prayer.allCases.count
        let fraction = CGFloat(min(status.count, total)) / CGFloat(total)
        let started = status.phase != .notStarted
        return VStack(spacing: 6) {
            Text(verbatim: topLabel(status))
                .font(.caption2.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(status.isComplete ? MorePalette.mint : MorePalette.secondaryText)
                .frame(height: 14)
            ZStack(alignment: .bottom) {
                if started {
                    Capsule()
                        .fill(status.isPaused ? TrackerPalette.pause.opacity(0.2) : TrackerPalette.track)
                } else {
                    Circle()
                        .fill(TrackerPalette.notStarted)
                        .frame(width: 5, height: 5)
                        .padding(.bottom, 2)
                }
                if status.count > 0 {
                    Capsule()
                        .fill(status.isComplete ? MorePalette.mint : MorePalette.mint.opacity(0.65))
                        .frame(height: max(10, Self.barHeight * fraction))
                }
                if status.isPaused, status.count == 0 {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TrackerPalette.pause)
                        .padding(.bottom, 7)
                }
            }
            .frame(maxWidth: 22)
            .frame(height: Self.barHeight)
            Text(day.shortName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.isToday ? MorePalette.gold : MorePalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(day)))
    }

    private func topLabel(_ status: TrackerDayStatus) -> String {
        if status.phase == .notStarted { return "" }
        if status.isPaused, status.count == 0 { return "" }
        return String(status.count)
    }

    private func accessibilityText(_ day: TrackerDay) -> String {
        let status = day.status
        if status.phase == .notStarted {
            return "\(day.fullName), not started"
        }
        if status.isPaused, status.count == 0 {
            return "\(day.fullName), paused"
        }
        return "\(day.fullName), \(status.count) of \(Prayer.allCases.count) marked"
    }
}
