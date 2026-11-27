import SwiftUI

/// Personal goals that forgive gaps. Each goal is a count toward a target: never a streak,
/// and nothing here lists what was not done.
struct GoalsView: View {
    @Environment(\.appClock) private var clock
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.scenePhase) private var scenePhase

    @State private var goals: [PersonalGoal] = []
    @State private var prayedDays: [String: Set<Prayer>] = [:]
    @State private var dhikr = DhikrTotals()
    @State private var today = Date()
    @State private var showsCreator = false
    @State private var revealed = false
    /// Goes up by one for each completion, for the success haptic.
    @State private var celebrations = 0
    /// Whole numbers at rest; animating to the next one pulses the celebrated card once.
    @State private var pulse: Double = 0
    @State private var celebratingID: UUID?

    private let store = GoalStore()
    private let prayedStore = PrayedStore()
    private let dhikrStore = DhikrLogStore()
    private let counter = GoalCounter()

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Goals", identifier: "goalsTitle")
                Text("Your own goals. Progress only counts up, and gaps are fine.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if goals.isEmpty {
                    emptyCard
                        .riseIn(revealed: revealed, delay: 0)
                }
                ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                    GoalCard(
                        goal: goal,
                        progress: counter.progress(for: goal, today: today, prayedDays: prayedDays, dhikr: dhikr),
                        isLoggedTonight: goal.loggedKeys.contains(counter.nightKey(for: today)),
                        pulse: goal.id == celebratingID ? pulse : 0,
                        onLog: { log(goal) },
                        onAdd: { changeCount(goal, by: 1) },
                        onSubtract: { changeCount(goal, by: -1) },
                        onRemove: { remove(goal) }
                    )
                    .riseIn(revealed: revealed, delay: 0.05 * Double(min(index, 6)))
                }
                addButton
                    .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.calendar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            revealed = true
            reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reload()
            }
        }
        .sensoryFeedback(.success, trigger: celebrations)
        .sheet(isPresented: $showsCreator) {
            GoalCreatorSheet { kind, target, name in
                create(kind: kind, target: target, name: name)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "flag")
                .font(.title2.weight(.semibold))
                .foregroundStyle(MorePalette.gold)
                .accessibilityHidden(true)
            Text("No goals yet")
                .font(.headline.weight(.heavy))
            Text("Pick a goal like 40 nights of night prayer. No deadline, and the days do not need to be in a row.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goalsEmpty")
    }

    private var addButton: some View {
        Button {
            showsCreator = true
        } label: {
            Label("Add a goal", systemImage: "plus.circle.fill")
                .font(.headline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(MorePalette.goldGradient)
                )
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier("goalsAdd")
    }

    // MARK: - Actions

    private func create(kind: GoalKind, target: Int, name: String) {
        let now = clock.now()
        let goal = PersonalGoal(
            kind: kind,
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(GoalCreatorSheet.nameLimit)),
            target: target,
            startKey: counter.dayKey(for: now)
        )
        store.add(goal)
        reload()
    }

    /// Logs tonight for a night prayer goal, or takes tonight's log back.
    private func log(_ goal: PersonalGoal) {
        var next = goal
        let key = counter.nightKey(for: clock.now())
        if next.loggedKeys.contains(key) {
            next.loggedKeys.removeAll { $0 == key }
        } else {
            next.loggedKeys.append(key)
        }
        store.update(next)
        reload()
    }

    private func changeCount(_ goal: PersonalGoal, by step: Int) {
        var next = goal
        next.manualCount = max(0, next.manualCount + step)
        store.update(next)
        reload()
    }

    private func remove(_ goal: PersonalGoal) {
        store.remove(id: goal.id)
        reload()
    }

    private func reload() {
        today = clock.now()
        prayedDays = prayedStore.allDays()
        dhikr = dhikrStore.load()
        var loaded = store.load()
        var celebrated: UUID?
        for index in loaded.indices {
            let goal = loaded[index]
            let progress = counter.progress(for: goal, today: today, prayedDays: prayedDays, dhikr: dhikr)
            if counter.needsCelebration(goal, progress: progress, today: today) {
                loaded[index].celebratedPeriod = counter.period(for: goal, today: today)
                store.update(loaded[index])
                celebrated = goal.id
            }
        }
        goals = loaded
        if let celebrated {
            celebrate(celebrated)
        }
    }

    private func celebrate(_ id: UUID) {
        celebrations += 1
        guard motionEnabled else { return }
        celebratingID = id
        withAnimation(.easeOut(duration: 0.9)) {
            pulse = floor(pulse) + 1
        }
    }
}

/// One goal: its title, a bar that fills toward the target, and a log button for manual goals.
private struct GoalCard: View {
    let goal: PersonalGoal
    let progress: GoalProgress
    let isLoggedTonight: Bool
    let pulse: Double
    let onLog: () -> Void
    let onAdd: () -> Void
    let onSubtract: () -> Void
    let onRemove: () -> Void

    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            bar
            HStack(alignment: .firstTextBaseline) {
                Text(progress.text)
                    .font(.title3.weight(.black))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(motionEnabled ? .easeOut(duration: 0.25) : nil, value: progress.count)
                    .accessibilityIdentifier("goalProgress-\(goal.kind.rawValue)")
                Spacer(minLength: 8)
                if progress.isComplete {
                    Label("Reached. Well done", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(MorePalette.mint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if goal.kind == .nightPrayer {
                nightButton
            } else if goal.kind == .custom {
                customButtons
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(MorePalette.goldLight, lineWidth: 3)
                .blur(radius: 3)
                .modifier(PulseEffect(progress: pulse, growth: 0.03))
                .allowsHitTesting(false)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goalCard-\(goal.kind.rawValue)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: goal.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.headline.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(goal.kind.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove goal", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Options for \(goal.title)"))
            .accessibilityIdentifier("goalMenu-\(goal.kind.rawValue)")
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(progress.fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(progress.isComplete ? AnyShapeStyle(MorePalette.mint) : AnyShapeStyle(MorePalette.goldGradient))
                    .frame(width: progress.count > 0 ? max(width, 10) : 0)
                    .animation(motionEnabled ? .easeOut(duration: 0.4) : nil, value: progress.fraction)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var nightButton: some View {
        Button(action: onLog) {
            Label(
                isLoggedTonight ? "Logged tonight. Tap to undo" : "Log tonight",
                systemImage: isLoggedTonight ? "checkmark.circle.fill" : "plus.circle"
            )
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(isLoggedTonight ? Color.white : MorePalette.ink)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(buttonBackground(filled: !isLoggedTonight))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityIdentifier("goalLog-\(goal.kind.rawValue)")
    }

    private var customButtons: some View {
        HStack(spacing: 8) {
            Button(action: onSubtract) {
                Image(systemName: "minus")
                    .font(.headline.weight(.heavy))
                    .frame(width: 56, height: 48)
                    .background(buttonBackground(filled: false))
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(goal.manualCount == 0)
            .opacity(goal.manualCount == 0 ? 0.5 : 1)
            .accessibilityLabel(Text("Take one away"))
            .accessibilityIdentifier("goalSubtract-\(goal.kind.rawValue)")

            Button(action: onAdd) {
                Label("Add one", systemImage: "plus")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(buttonBackground(filled: true))
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("goalAdd-\(goal.kind.rawValue)")
        }
    }

    @ViewBuilder
    private func buttonBackground(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if filled {
            shape.fill(MorePalette.goldGradient)
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}
