import SwiftUI

/// Prayer tracker: streaks, this week's dots, a 7 day trend, per prayer totals, pause mode,
/// a fasting log and history by month. Counting starts on the first day the user tracked.
struct TrackerView: View {
    @Environment(\.appClock) private var clock
    @Environment(\.motionEnabled) private var motionEnabled

    @State private var history = TrackerHistory(days: [:], pauses: [], calculator: StreakCalculator())
    @State private var today = Date()
    @State private var monthsBack = 0
    @State private var monthFasts: Set<String> = []
    @State private var fasting = TrackerFastingState(isRamadan: false, count: 0, loggedToday: false)
    @State private var showsPauseEditor = false
    @State private var revealed = false

    private let store = PrayedStore()
    private let pauseStore = PauseStore()
    private let fastingStore = FastingLogStore()
    private let calculator = StreakCalculator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Your prayers", identifier: "trackerTitle")
                streakCard
                    .riseIn(revealed: revealed, delay: 0)
                weekCard
                    .riseIn(revealed: revealed, delay: 0.05)
                TrackerTrendCard(days: TrackerDay.days(history.lastDays(7, endingOn: today), today: today, history: history))
                    .riseIn(revealed: revealed, delay: 0.1)
                totalsCard
                    .riseIn(revealed: revealed, delay: 0.15)
                pauseCard
                    .riseIn(revealed: revealed, delay: 0.2)
                fastingCard
                    .riseIn(revealed: revealed, delay: 0.25)
                monthCard
                    .riseIn(revealed: revealed, delay: 0.3)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.tracker)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            revealed = true
            reload()
        }
        .sheet(isPresented: $showsPauseEditor) {
            PauseEditorView(today: today, calculator: calculator) { pause in
                pauseStore.save(pause)
                reload()
            }
        }
    }

    // MARK: - Streak

    private var streakCard: some View {
        let current = history.currentStreak(today: today)
        let best = history.bestStreak()
        let pause = history.activePause(on: today)
        return VStack(alignment: .leading, spacing: 6) {
            MoreCaption(text: "Current streak")
            Text(Self.daysText(current))
                .font(.system(size: 64, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("currentStreak")
            Text("Best: \(Self.daysText(best))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityIdentifier("bestStreak")
            if let pause {
                Label("Paused: \(pause.reason.title). Your streak is held.", systemImage: pause.reason.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TrackerPalette.pause)
                    .padding(.top, 4)
            } else if !history.hasTracked {
                Text("Mark a prayer to begin. Counting starts that day.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Week strip

    private var weekCard: some View {
        let days = TrackerDay.days(history.week(containing: today), today: today, history: history)
        let showsPaused = days.contains { $0.status.isPaused }
        let showsNotStarted = days.contains { $0.status.phase == .notStarted }
        return VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.headline.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                ForEach(days) { day in
                    weekColumn(day)
                }
            }
            weekLegend(showsPaused: showsPaused, showsNotStarted: showsNotStarted)
        }
        .padding(16)
        .moreGlass(.dark, cornerRadius: 28)
    }

    private func weekColumn(_ day: TrackerDay) -> some View {
        VStack(spacing: 0) {
            Text(day.shortName)
                .font(.caption.weight(.bold))
                .foregroundStyle(day.isToday ? MorePalette.gold : MorePalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            ForEach(Prayer.allCases) { prayer in
                dot(day: day, prayer: prayer)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            if day.status.isPaused {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TrackerPalette.pause.opacity(0.14))
                    .padding(.horizontal, 2)
            }
        }
    }

    private func dot(day: TrackerDay, prayer: Prayer) -> some View {
        let prayed = day.prayed.contains(prayer)
        return Button {
            toggle(prayer, on: day)
        } label: {
            dotMark(prayed: prayed, status: day.status)
                .frame(width: 18, height: 18)
                .animation(motionEnabled ? .spring(response: 0.35, dampingFraction: 0.65) : nil, value: prayed)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .opacity(day.isFuture ? 0.35 : 1)
        .accessibilityLabel(Text("\(day.fullName), \(prayer.displayName), \(Self.dotState(prayed: prayed, status: day.status))"))
        .accessibilityAddTraits(prayed ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("dot-\(day.key)-\(prayer.rawValue)")
    }

    /// Prayed: a mint dot. Not marked: a white ring. Paused: a dashed soft ring.
    /// Before the user started: a faint blank point, never a ring.
    private func dotMark(prayed: Bool, status: TrackerDayStatus) -> some View {
        let blank = !prayed && status.phase == .notStarted
        let pausedRing = !prayed && status.isPaused
        let ringColor: Color
        if prayed {
            ringColor = MorePalette.mint
        } else if pausedRing {
            ringColor = TrackerPalette.pause.opacity(0.85)
        } else if blank {
            ringColor = Color.clear
        } else {
            ringColor = Color.white.opacity(0.6)
        }
        return ZStack {
            Circle()
                .fill(prayed ? MorePalette.mint : (blank ? TrackerPalette.notStarted : Color.clear))
                .scaleEffect(prayed ? 1 : 0.34)
            Circle()
                .strokeBorder(ringColor, style: StrokeStyle(lineWidth: 2, dash: pausedRing ? [3, 3] : []))
        }
    }

    private func weekLegend(showsPaused: Bool, showsNotStarted: Bool) -> some View {
        HStack(spacing: 12) {
            legendItem("Prayed") {
                Circle().fill(MorePalette.mint)
            }
            legendItem("Not marked") {
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
            }
            if showsPaused {
                legendItem("Paused") {
                    Circle().strokeBorder(TrackerPalette.pause, style: StrokeStyle(lineWidth: 2, dash: [2, 2]))
                }
            }
            if showsNotStarted {
                legendItem("Not started") {
                    Circle().fill(TrackerPalette.notStarted).padding(3)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MorePalette.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityHidden(true)
    }

    private func legendItem<Mark: View>(_ title: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
                .frame(width: 10, height: 10)
            Text(title)
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let totals = history.perPrayerTotals()
        let full = history.fullDayCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Prayers marked")
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(sinceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 0) {
                ForEach(Prayer.allCases) { prayer in
                    VStack(spacing: 2) {
                        Text(verbatim: String(totals[prayer] ?? 0))
                            .font(.title2.weight(.black))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(prayer.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MorePalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("total-\(prayer.rawValue)")
                }
            }
            Text(verbatim: full == 1 ? "1 day with all five" : "\(full) days with all five")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.mint)
                .accessibilityIdentifier("fullDayCount")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
    }

    private var sinceText: String {
        guard let key = history.firstTrackedKey, let date = calculator.date(fromKey: key) else {
            return "Starts when you mark a prayer"
        }
        return "Since " + history.formatter(template: "dMMMy").string(from: date)
    }

    // MARK: - Pause

    private var pauseCard: some View {
        let active = history.activePause(on: today)
        let others = Array(history.pauses.filter { $0.id != active?.id }.prefix(3))
        return VStack(alignment: .leading, spacing: 12) {
            if let active {
                activePauseContent(active)
            } else {
                startPauseContent
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(others) { pause in
                        pauseRow(pause)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
    }

    private var startPauseContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Need a break?")
                .font(.headline.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            Text("Pause for travel, illness or a monthly break. Paused days hold your streak and are not counted.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsPauseEditor = true
            } label: {
                Label("Start a pause", systemImage: "pause.circle")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(TrackerPalette.pause.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(TrackerPalette.pause.opacity(0.7), lineWidth: 1)
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("trackerStartPause")
        }
    }

    private func activePauseContent(_ pause: TrackerPause) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Paused: \(pause.reason.title)", systemImage: pause.reason.symbol)
                .font(.headline.weight(.heavy))
                .foregroundStyle(TrackerPalette.pause)
                .accessibilityAddTraits(.isHeader)
            Text(rangeText(pause) + ". Your streak is held while you are paused.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                resume(pause)
            } label: {
                Label("Resume tracking", systemImage: "play.circle")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(MorePalette.goldGradient)
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("trackerEndPause")
        }
    }

    private func pauseRow(_ pause: TrackerPause) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pause.reason.symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(TrackerPalette.pause)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(pause.reason.title)
                    .font(.footnote.weight(.heavy))
                Text(rangeText(pause))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            Spacer(minLength: 8)
            Button {
                pauseStore.remove(id: pause.id)
                reload()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(pause.reason.title) pause"))
        }
        .accessibilityElement(children: .contain)
    }

    private func rangeText(_ pause: TrackerPause) -> String {
        let formatter = history.formatter(template: "dMMM")
        let start = calculator.date(fromKey: pause.startKey).map { formatter.string(from: $0) } ?? pause.startKey
        guard let endKey = pause.endKey else {
            return "Since \(start)"
        }
        if endKey == pause.startKey {
            return start
        }
        let end = calculator.date(fromKey: endKey).map { formatter.string(from: $0) } ?? endKey
        return "\(start) to \(end)"
    }

    private func resume(_ pause: TrackerPause) {
        let day = calculator.calendar.startOfDay(for: today)
        let yesterday = calculator.calendar.date(byAdding: .day, value: -1, to: day) ?? day
        pauseStore.end(pause, lastPausedKey: calculator.dayKey(for: yesterday))
        reload()
    }

    // MARK: - Fasting

    private var fastingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(fasting.isRamadan ? "Ramadan fasts" : "Voluntary fasts")
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(verbatim: fasting.count == 1 ? "1 logged" : "\(fasting.count) logged")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.mint)
                    .accessibilityIdentifier("trackerFastCount")
            }
            Button(action: toggleFast) {
                Label(
                    fasting.loggedToday ? "Logged today. Tap to undo" : "Log a fast today",
                    systemImage: fasting.loggedToday ? "checkmark.circle.fill" : "plus.circle"
                )
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(fasting.loggedToday ? Color.white : MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(fastButtonBackground)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("trackerLogFast")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
    }

    @ViewBuilder
    private var fastButtonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if fasting.loggedToday {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(MorePalette.mint, lineWidth: 1))
        } else {
            shape.fill(MorePalette.goldGradient)
        }
    }

    private var ramadanCalendar: RamadanCalendar {
        RamadanCalendar(timeZone: calculator.calendar.timeZone)
    }

    private func toggleFast() {
        guard let hijri = ramadanCalendar.hijriDay(for: today) else { return }
        if hijri.month == RamadanCalendar.ramadanMonth {
            fastingStore.setFasted(!fastingStore.isFasted(day: hijri.day, year: hijri.year), day: hijri.day, year: hijri.year)
        } else {
            fastingStore.setVoluntaryFast(!fastingStore.isVoluntaryFastLogged(on: hijri), on: hijri)
        }
        reloadFasting()
    }

    private func reloadFasting() {
        let calendar = ramadanCalendar
        if let hijri = calendar.hijriDay(for: today) {
            if hijri.month == RamadanCalendar.ramadanMonth {
                fasting = TrackerFastingState(
                    isRamadan: true,
                    count: fastingStore.fastedDays(inRamadanOf: hijri.year).count,
                    loggedToday: fastingStore.isFasted(day: hijri.day, year: hijri.year)
                )
            } else {
                fasting = TrackerFastingState(
                    isRamadan: false,
                    count: fastingStore.voluntaryFastCount,
                    loggedToday: fastingStore.isVoluntaryFastLogged(on: hijri)
                )
            }
        } else {
            fasting = TrackerFastingState(isRamadan: false, count: fastingStore.voluntaryFastCount, loggedToday: false)
        }
        monthFasts = fastedKeys(in: displayedMonth, calendar: calendar)
    }

    private func fastedKeys(in month: TrackerMonth, calendar: RamadanCalendar) -> Set<String> {
        var keys: Set<String> = []
        for date in month.dates {
            if let hijri = calendar.hijriDay(for: date), fastingStore.hasFastLogged(on: hijri) {
                keys.insert(calculator.dayKey(for: date))
            }
        }
        return keys
    }

    // MARK: - History by month

    private var monthStarts: [Date] {
        history.monthStarts(today: today)
    }

    private var displayedMonth: TrackerMonth {
        let starts = monthStarts
        guard !starts.isEmpty else {
            return history.month(startingAt: history.monthStart(containing: today))
        }
        let index = max(0, starts.count - 1 - monthsBack)
        return history.month(startingAt: starts[index])
    }

    private var monthCard: some View {
        let count = monthStarts.count
        return TrackerMonthCard(
            history: history,
            today: today,
            month: displayedMonth,
            fastedKeys: monthFasts,
            canGoBack: monthsBack < count - 1,
            canGoForward: monthsBack > 0,
            goBack: { changeMonth(by: 1) },
            goForward: { changeMonth(by: -1) }
        )
    }

    private func changeMonth(by step: Int) {
        let limit = max(0, monthStarts.count - 1)
        monthsBack = min(max(monthsBack + step, 0), limit)
        monthFasts = fastedKeys(in: displayedMonth, calendar: ramadanCalendar)
    }

    // MARK: - Loading

    private func toggle(_ prayer: Prayer, on day: TrackerDay) {
        guard !day.isFuture else { return }
        store.setPrayed(!day.prayed.contains(prayer), prayer, on: day.date)
        reload()
    }

    private func reload() {
        today = clock.now()
        history = TrackerHistory.load(calculator: calculator)
        monthsBack = min(monthsBack, max(0, history.monthStarts(today: today).count - 1))
        reloadFasting()
    }

    private static func daysText(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    private static func dotState(prayed: Bool, status: TrackerDayStatus) -> String {
        if prayed { return "prayed" }
        if status.phase == .notStarted { return "not started" }
        if status.isPaused { return "paused" }
        return "not marked"
    }
}

/// What the fasting card shows for today.
struct TrackerFastingState: Equatable {
    let isRamadan: Bool
    let count: Int
    let loggedToday: Bool
}
