import SwiftUI

/// History by month: a month picker and a day grid. Days before the user started and future
/// days show only their number; paused days get a soft periwinkle; a gold dot marks a logged fast.
struct TrackerMonthCard: View {
    let history: TrackerHistory
    let today: Date
    let month: TrackerMonth
    let fastedKeys: Set<String>
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let todayKey = history.calculator.dayKey(for: today)
        let statuses = month.dates.map { history.status(for: $0, today: today) }
        let dayFormatter = history.formatter(template: "MMMMd")
        let leading = max(0, month.leadingBlanks)
        return VStack(alignment: .leading, spacing: 12) {
            header
            weekdayRow
            LazyVGrid(columns: columns, spacing: 6) {
                // One slot per grid position: leading blanks, then the days, so every id is unique.
                ForEach(0..<(leading + statuses.count), id: \.self) { slot in
                    if slot < leading {
                        Color.clear
                            .frame(height: 36)
                            .accessibilityHidden(true)
                    } else {
                        cell(
                            date: month.dates[slot - leading],
                            status: statuses[slot - leading],
                            isToday: statuses[slot - leading].key == todayKey,
                            formatter: dayFormatter
                        )
                    }
                }
            }
            Text(summaryText(statuses))
                .font(.caption.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityIdentifier("historySummary")
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            monthButton(symbol: "chevron.left", label: "Previous month", identifier: "historyPrevious", enabled: canGoBack, action: goBack)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                MoreCaption(text: "History")
                Text(history.formatter(template: "MMMMy").string(from: month.start))
                    .font(.headline.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("historyMonthTitle")
            }
            Spacer(minLength: 0)
            monthButton(symbol: "chevron.right", label: "Next month", identifier: "historyNext", enabled: canGoForward, action: goForward)
        }
    }

    private func monthButton(symbol: String, label: String, identifier: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(enabled ? 0.1 : 0.04)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private var weekdayRow: some View {
        let symbols = history.weekdaySymbols
        return HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Cells

    private func cell(date: Date, status: TrackerDayStatus, isToday: Bool, formatter: DateFormatter) -> some View {
        let dayNumber = history.displayCalendar.component(.day, from: date)
        let fasted = fastedKeys.contains(status.key)
        return ZStack {
            cellBackground(status)
            Text(verbatim: String(dayNumber))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(textColor(status))
        }
        .frame(height: 36)
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MorePalette.gold, lineWidth: 1.5)
            }
        }
        .overlay(alignment: .bottom) {
            if fasted {
                Circle()
                    .fill(MorePalette.gold)
                    .frame(width: 5, height: 5)
                    .padding(.bottom, 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(name: formatter.string(from: date), status: status, fasted: fasted)))
        .accessibilityIdentifier("historyDay-\(status.key)")
    }

    @ViewBuilder
    private func cellBackground(_ status: TrackerDayStatus) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        switch status.phase {
        case .notStarted:
            Color.clear
        case .future:
            if status.isPaused {
                shape.fill(TrackerPalette.pause.opacity(0.12))
            } else {
                Color.clear
            }
        case .active:
            if status.isComplete {
                shape.fill(MorePalette.mint)
            } else if status.isPaused {
                shape.fill(TrackerPalette.pause.opacity(0.26))
            } else if status.count > 0 {
                shape.fill(MorePalette.mint.opacity(0.14 + 0.1 * Double(status.count)))
            } else {
                shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
        }
    }

    private func textColor(_ status: TrackerDayStatus) -> Color {
        switch status.phase {
        case .notStarted:
            return Color.white.opacity(0.4)
        case .future:
            return Color.white.opacity(0.45)
        case .active:
            return status.isComplete ? MorePalette.ink : Color.white
        }
    }

    private func accessibilityText(name: String, status: TrackerDayStatus, fasted: Bool) -> String {
        var state: String
        switch status.phase {
        case .notStarted:
            state = "not started"
        case .future:
            state = status.isPaused ? "pause planned" : "upcoming"
        case .active:
            if status.isComplete {
                state = "all five marked"
            } else if status.isPaused {
                state = status.count > 0 ? "paused, \(status.count) of 5 marked" : "paused"
            } else if status.count > 0 {
                state = "\(status.count) of 5 marked"
            } else {
                state = "not marked"
            }
        }
        if fasted {
            state += ", fast logged"
        }
        return "\(name), \(state)"
    }

    // MARK: - Summary and legend

    private func summaryText(_ statuses: [TrackerDayStatus]) -> String {
        let active = statuses.filter { $0.phase == .active }
        let full = active.filter(\.isComplete).count
        let marked = active.reduce(0) { $0 + $1.count }
        let fullText = full == 1 ? "1 day with all five" : "\(full) days with all five"
        let markedText = marked == 1 ? "1 prayer marked" : "\(marked) prayers marked"
        return "\(fullText), \(markedText)"
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("All five") {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(MorePalette.mint)
            }
            legendItem("Some") {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(MorePalette.mint.opacity(0.45))
            }
            legendItem("Paused") {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(TrackerPalette.pause.opacity(0.5))
            }
            legendItem("Fast") {
                Circle().fill(MorePalette.gold).padding(2)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(MorePalette.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    private func legendItem<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 4) {
            mark()
                .frame(width: 10, height: 10)
            Text(title)
        }
    }
}
