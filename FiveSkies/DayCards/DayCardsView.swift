import SwiftUI

/// Small glass reminders for Today: Friday, Ramadan, the white days, Monday and Thursday,
/// the Eid days and the Day of Arafah. At most two show. Each can be hidden for the day.
/// Shows nothing when no card applies. Carries its own padding, so place it without any.
/// No timer of its own: it follows `now`, which Today already refreshes.
struct DayCardsView: View {
    let now: Date
    let timeZone: TimeZone

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.motionEnabled) private var motionEnabled
    /// Bumped on each dismissal, so the view reads the store again and plays a light haptic.
    @State private var dismissCount = 0

    private let store: DayCardDismissals
    private let overrideDate: Date?

    init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
        store = DayCardDismissals()
        overrideDate = DayCardsLaunchOptions().date(in: timeZone)
    }

    var body: some View {
        let rules = DayCardRules(timeZone: timeZone, hijriAdjustment: settings.hijriAdjustment)
        let date = overrideDate ?? now
        let key = rules.dayKey(for: date)
        // Reading `dismissCount` here ties the store read to each dismissal.
        let _ = dismissCount
        let shown = rules.cards(for: date, hiding: store.hidden(on: key))
        // An empty stack takes no space, and keeps the haptic alive when the last card goes.
        VStack(spacing: 0) {
            if !shown.isEmpty {
                row(shown, dayKey: key)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("dayCards")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: dismissCount)
    }

    private func row(_ cards: [DayCard], dayKey: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(cards) { card in
                    cardView(card, dayKey: dayKey)
                }
            }
            // Too wide side by side: stack them, each full width, so no text is cut off.
            VStack(spacing: 8) {
                ForEach(cards) { card in
                    cardView(card, dayKey: dayKey)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func cardView(_ card: DayCard, dayKey: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return HStack(spacing: 9) {
            Image(systemName: card.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MorePalette.gold)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dayCard-\(card.id)")
            Spacer(minLength: 0)
            Button {
                dismiss(card, dayKey: dayKey)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 30, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.85))
            .accessibilityLabel(Text("Hide for today"))
            .accessibilityIdentifier("dayCardHide-\(card.id)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: 50)
        .background(shape.fill(Color(hex: 0x120B1F, opacity: 0.55)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .transition(.opacity)
    }

    private func dismiss(_ card: DayCard, dayKey: String) {
        store.hide(card.id, on: dayKey)
        if motionEnabled {
            withAnimation(.easeOut(duration: 0.25)) {
                dismissCount += 1
            }
        } else {
            dismissCount += 1
        }
    }
}
