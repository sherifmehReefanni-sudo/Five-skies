import SwiftUI
import UIKit

/// Tasbih counter: pick a phrase and a target, tap the circle to count.
/// Below the counter: today's total across all phrases, an optional daily goal,
/// the last seven days and the total this week.
struct TasbihView: View {
    @AppStorage("tasbih.count") private var storedCount = 0
    @AppStorage("tasbih.target") private var storedTarget = TasbihCounter.defaultTarget
    @AppStorage("tasbih.rounds") private var storedRounds = 0
    @AppStorage("tasbih.phrase") private var phrase: TasbihPhrase = .subhanAllah
    @AppStorage("tasbih.haptics") private var hapticsOn = true
    @AppStorage(DhikrLogStore.dailyGoalKey) private var dailyGoal = 0

    @ScaledMetric(relativeTo: .largeTitle) private var countSize: CGFloat = 88
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.appClock) private var clock
    @Environment(\.scenePhase) private var scenePhase
    /// Whole numbers at rest; animating to the next one pulses the ring once when a round completes.
    @State private var roundPulse: Double = 0
    /// Daily dhikr totals across every phrase.
    @State private var totals = DhikrTotals()
    @State private var now = Date()
    /// Goes up by one each time the daily goal is reached, for the success haptic.
    @State private var goalReached = 0
    /// Whole numbers at rest; animating to the next one pulses the today card once.
    @State private var goalPulse: Double = 0

    private let dhikrStore = DhikrLogStore()

    private let circleSize: CGFloat = 250

    private var counter: TasbihCounter {
        TasbihCounter(count: storedCount, target: storedTarget, rounds: storedRounds)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MoreScreenTitle(text: "Tasbih", identifier: "tasbihTitle")
                phrasePicker
                counterButton
                    .padding(.vertical, 8)
                controls
                roundsRow
                Text("Tap the circle to count. It starts over after the target.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MorePalette.secondaryText)
                    .multilineTextAlignment(.center)
                todayCard
                    .padding(.top, 8)
                weekCard
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.tasbih)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reloadTotals)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reloadTotals()
            }
        }
        .sensoryFeedback(trigger: goalReached) { _, _ in
            hapticsOn ? .success : nil
        }
    }

    private var phrasePicker: some View {
        HStack(spacing: 8) {
            ForEach(TasbihPhrase.allCases) { item in
                let selected = item == phrase
                Button {
                    if !selected {
                        phrase = item
                        storedCount = 0
                    }
                } label: {
                    Text(item.title)
                        .font(.footnote.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? MorePalette.ink : Color.white)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(pill(selected: selected))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                .accessibilityIdentifier("tasbihPhrase-\(item.rawValue)")
            }
        }
    }

    private var counterButton: some View {
        let current = counter
        return Button(action: tap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                Circle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    .padding(12)
                Circle()
                    .trim(from: 0, to: CGFloat(current.progress))
                    .stroke(MorePalette.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(12)
                    .animation(motionEnabled ? .easeOut(duration: 0.25) : nil, value: current.count)
                Circle()
                    .stroke(MorePalette.goldLight, lineWidth: 12)
                    .blur(radius: 4)
                    .padding(12)
                    .modifier(PulseEffect(progress: roundPulse, growth: 0.05))
                    .allowsHitTesting(false)
                VStack(spacing: 2) {
                    Text("\(current.count)")
                        .font(.system(size: countSize, weight: .black))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .animation(motionEnabled ? .easeOut(duration: 0.25) : nil, value: current.count)
                    Text("of \(current.target)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                .padding(36)
            }
            .frame(width: circleSize, height: circleSize)
            .contentShape(Circle())
            .shadow(color: MorePalette.gold.opacity(0.18), radius: 30, y: 20)
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.97))
        .accessibilityLabel(Text("Count \(phrase.title), target \(current.target)"))
        .accessibilityValue(Text("\(current.count)"))
        .accessibilityHint(Text("Tap to count"))
        .accessibilityIdentifier("tasbihCounter")
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .moreGlass(.light, cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tasbihReset")

                ForEach(TasbihCounter.targets, id: \.self) { value in
                    let selected = value == counter.target
                    Button {
                        var next = counter
                        next.setTarget(value)
                        save(next)
                    } label: {
                        Text("\(value)")
                            .font(.headline.weight(.black))
                            .foregroundStyle(selected ? MorePalette.ink : MorePalette.gold)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(pill(selected: selected))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Target \(value)"))
                    .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("tasbihTarget-\(value)")
                }
            }

            Toggle(isOn: $hapticsOn) {
                Text("Vibration")
                    .font(.subheadline.weight(.heavy))
            }
            .tint(MorePalette.mint)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .moreGlass(.light, cornerRadius: 22)
            .accessibilityIdentifier("tasbihHaptics")
        }
    }

    private var roundsRow: some View {
        HStack {
            Text("Rounds completed")
                .font(.subheadline.weight(.bold))
            Spacer(minLength: 8)
            Text("\(counter.rounds)")
                .font(.headline.weight(.black))
                .foregroundStyle(MorePalette.mint)
                .accessibilityIdentifier("tasbihRounds")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .moreGlass(.light, cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pill(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if selected {
            shape.fill(MorePalette.goldGradient)
                .overlay(shape.strokeBorder(Color.white, lineWidth: 1))
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        }
    }

    // MARK: - Dhikr stats

    private var todayKey: String {
        dhikrStore.counter.dayKey(for: now)
    }

    private var todayCard: some View {
        let total = totals.total(on: todayKey)
        let goal = GoalProgress(count: total, target: dailyGoal)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                MoreCaption(text: "Today, all phrases")
                Spacer(minLength: 8)
                goalMenu
            }
            Text(verbatim: String(total))
                .font(.system(size: 44, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(motionEnabled ? .easeOut(duration: 0.25) : nil, value: total)
                .accessibilityLabel(Text("Today's total"))
                .accessibilityValue(Text(verbatim: String(total)))
                .accessibilityIdentifier("dhikrTodayTotal")
            if dailyGoal > 0 {
                goalBar(goal)
                HStack {
                    Text(verbatim: "\(goal.text) today")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(MorePalette.secondaryText)
                    Spacer(minLength: 8)
                    if goal.isComplete {
                        Label("Reached", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(MorePalette.mint)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dhikrGoalProgress")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(MorePalette.mint, lineWidth: 3)
                .blur(radius: 3)
                .modifier(PulseEffect(progress: goalPulse, growth: 0.03))
                .allowsHitTesting(false)
        )
    }

    private var goalMenu: some View {
        Menu {
            ForEach(DhikrLogStore.dailyGoalChoices, id: \.self) { choice in
                Button {
                    dailyGoal = choice
                } label: {
                    if choice == dailyGoal {
                        Label(Self.goalTitle(choice), systemImage: "checkmark")
                    } else {
                        Text(Self.goalTitle(choice))
                    }
                }
            }
        } label: {
            Label(dailyGoal > 0 ? "Goal \(dailyGoal)" : "Set a goal", systemImage: "flag")
                .font(.footnote.weight(.heavy))
                .foregroundStyle(MorePalette.gold)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(Text(dailyGoal > 0 ? "Daily goal, \(dailyGoal)" : "Set a daily goal"))
        .accessibilityIdentifier("dhikrDailyGoal")
    }

    private func goalBar(_ goal: GoalProgress) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(goal.isComplete ? AnyShapeStyle(MorePalette.mint) : AnyShapeStyle(MorePalette.goldGradient))
                    .frame(width: goal.count > 0 ? max(proxy.size.width * CGFloat(goal.fraction), 10) : 0)
                    .animation(motionEnabled ? .easeOut(duration: 0.3) : nil, value: goal.fraction)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var weekCard: some View {
        let math = dhikrStore.counter
        let days = math.lastDays(7, endingOn: now)
        let values = days.map { totals.total(on: math.dayKey(for: $0)) }
        let largest = max(values.max() ?? 0, 1)
        let weekTotal = totals.sum(of: math.weekKeys(containing: now))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days")
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(verbatim: "This week: \(weekTotal)")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.mint)
                    .accessibilityIdentifier("dhikrWeekTotal")
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    dayBar(day: day, value: values[index], largest: largest, isToday: index == days.count - 1)
                }
            }
            .frame(height: 132)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dhikrWeekChart")
    }

    private func dayBar(day: Date, value: Int, largest: Int, isToday: Bool) -> some View {
        let height = 84 * CGFloat(value) / CGFloat(largest)
        return VStack(spacing: 4) {
            Text(verbatim: value > 0 ? String(value) : " ")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(MorePalette.secondaryText)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isToday ? AnyShapeStyle(MorePalette.goldGradient) : AnyShapeStyle(Color.white.opacity(0.55)))
                .frame(height: value > 0 ? max(height, 6) : 3)
                .opacity(value > 0 ? 1 : 0.4)
                .animation(motionEnabled ? .easeOut(duration: 0.3) : nil, value: value)
            Text(Self.weekdayFormatter.string(from: day))
                .font(.caption.weight(.bold))
                .foregroundStyle(isToday ? MorePalette.gold : MorePalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.fullDayFormatter.string(from: day)))
        .accessibilityValue(Text(verbatim: String(value)))
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private static func goalTitle(_ choice: Int) -> String {
        choice > 0 ? "\(choice) a day" : "No daily goal"
    }

    private func reloadTotals() {
        now = clock.now()
        totals = dhikrStore.load()
    }

    /// Adds one tap to today's total and celebrates once when the daily goal is reached.
    private func recordTap() {
        let date = clock.now()
        let key = dhikrStore.counter.dayKey(for: date)
        let before = dhikrStore.load().total(on: key)
        let updated = dhikrStore.add(1, at: date)
        let after = updated.total(on: key)
        now = date
        totals = updated
        guard dailyGoal > 0, before < dailyGoal, after >= dailyGoal else { return }
        goalReached += 1
        if motionEnabled {
            withAnimation(.easeOut(duration: 0.9)) {
                goalPulse = floor(goalPulse) + 1
            }
        }
    }

    // MARK: - Counting

    private func tap() {
        var next = counter
        next.increment()
        save(next)
        recordTap()
        if next.count == next.target && motionEnabled {
            withAnimation(.easeOut(duration: 0.8)) {
                roundPulse = floor(roundPulse) + 1
            }
        }
        if hapticsOn {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func reset() {
        var next = counter
        next.reset()
        save(next)
    }

    private func save(_ value: TasbihCounter) {
        storedCount = value.count
        storedTarget = value.target
        storedRounds = value.rounds
    }
}
