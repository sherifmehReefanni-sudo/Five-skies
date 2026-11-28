import SwiftUI

/// The reading plan: pick how to pace it, then one portion of pages a day with a quiet ring.
/// A skipped day just spreads the rest again. Pushed inside the Learn tab's NavigationStack.
@MainActor
struct ReadingPlanView: View {
    let data: QuranData
    let onOpen: (QuranReaderTarget) -> Void

    @ObservedObject private var store: ReadingPlanStore

    @Environment(\.appClock) private var clock
    @Environment(\.scenePhase) private var scenePhase

    /// Read from the clock on appear and whenever the app comes back, so a new day shows.
    @State private var today = Date()
    @State private var isChoosing = false
    @State private var pace = ReadingPlanKind.defaultPace
    @State private var pendingKind: ReadingPlanKind?
    @State private var confirmsChange = false
    /// Goes up by one for each portion marked done, for the success haptic.
    @State private var doneCount = 0

    private let calendar = Calendar.current

    init(data: QuranData, onOpen: @escaping (QuranReaderTarget) -> Void) {
        self.data = data
        self.onOpen = onOpen
        _store = ObservedObject(wrappedValue: ReadingPlanStore.shared)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MoreScreenTitle(text: "Reading plan", identifier: "readingPlanTitle")
                Text("Finish in 30, 60 or 365 days, or at your own pace.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                if let plan = store.plan, !isChoosing {
                    if plan.isFinished {
                        finishedCard(plan)
                    } else {
                        planCard(plan)
                    }
                } else {
                    choices
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .quranSkyBackground()
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("readingPlan")
        .onAppear {
            today = clock.now()
            store.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                today = clock.now()
                store.reload()
            }
        }
        .sensoryFeedback(.success, trigger: doneCount)
        .confirmationDialog("Change your plan?", isPresented: $confirmsChange, titleVisibility: .visible) {
            Button("Change plan") {
                if let kind = pendingKind {
                    store.change(to: kind, today: today)
                }
                pendingKind = nil
                isChoosing = false
            }
            Button("Cancel", role: .cancel) {
                pendingKind = nil
            }
        } message: {
            Text("The pages you have read stay read. What is left is spread over the new plan, starting today.")
        }
    }

    // MARK: - Choosing a plan

    private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ReadingPlanKind.dayChoices, id: \.self) { days in
                Button {
                    choose(.days(days))
                } label: {
                    ReadingPlanChoiceLabel(
                        title: ReadingPlanKind.days(days).title,
                        detail: "About \(ReadingPlanText.pagesPerDay(ReadingPlanMath.pagesPerDay(forDays: days)))",
                        symbol: "calendar"
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("planDays\(days)")
            }

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    choose(.pace(pagesPerDay: pace))
                } label: {
                    ReadingPlanChoiceLabel(
                        title: "My own pace",
                        detail: ReadingPlanText.pagesPerDay(pace),
                        symbol: "leaf",
                        hasGlass: false
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("planPace")

                Picker("Pages a day", selection: $pace) {
                    ForEach(ReadingPlanKind.paceChoices, id: \.self) { count in
                        Text(verbatim: String(count)).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .accessibilityIdentifier("planPacePicker")
            }
            .moreGlass(.light, cornerRadius: 22)

            if store.plan != nil {
                Button {
                    isChoosing = false
                } label: {
                    Text("Keep my plan")
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ReadingPlanButtonFill(filled: false))
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, 4)
                .accessibilityIdentifier("planKeep")
            }
        }
    }

    private func choose(_ kind: ReadingPlanKind) {
        if store.plan == nil {
            store.start(kind, today: today)
            isChoosing = false
        } else {
            pendingKind = kind
            confirmsChange = true
        }
    }

    // MARK: - A plan in progress

    private func planCard(_ plan: ReadingPlan) -> some View {
        let doneToday = plan.isDone(on: today, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let range = plan.portion(on: doneToday ? tomorrow : today, calendar: calendar)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                ReadingPlanRing(pagesRead: plan.pagesRead)
                VStack(alignment: .leading, spacing: 6) {
                    MoreCaption(text: plan.kind.title)
                    if let range {
                        Text(verbatim: doneToday
                             ? "Next time: \(ReadingPlanText.pages(range))"
                             : ReadingPlanText.todayLine(range))
                            .font(.title3.weight(.heavy))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("planToday")
                        if let start = startLine(for: range.lowerBound) {
                            Text(verbatim: start)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MorePalette.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("planStartsAt")
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let range {
                Button {
                    open(page: range.lowerBound)
                } label: {
                    Label(doneToday ? "Open the next pages" : "Open today's reading", systemImage: "book")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(MorePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(ReadingPlanButtonFill(filled: true))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("planOpenToday")
            }

            Button {
                if store.markTodayDone(today: today, calendar: calendar) {
                    doneCount += 1
                }
            } label: {
                Label(
                    doneToday ? ReadingPlanText.doneForToday : "I read today's portion",
                    systemImage: doneToday ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(doneToday ? MorePalette.mint : Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(ReadingPlanButtonFill(filled: false))
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(doneToday)
            .accessibilityIdentifier("planDone")

            Button {
                if case .pace(let pagesPerDay) = plan.kind, ReadingPlanKind.paceChoices.contains(pagesPerDay) {
                    pace = pagesPerDay
                }
                isChoosing = true
            } label: {
                Text("Change plan")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("planChange")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planCard")
    }

    private func finishedCard(_ plan: ReadingPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                ReadingPlanRing(pagesRead: plan.pagesRead)
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(QuranPalette.gold)
                        .accessibilityHidden(true)
                    Text(ReadingPlanText.finished)
                        .font(.title3.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("planFinished")
                }
                Spacer(minLength: 0)
            }
            Button {
                store.startAgain(today: today)
            } label: {
                Label("Start again", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ReadingPlanButtonFill(filled: true))
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("planStartAgain")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planCard")
    }

    // MARK: - Pages

    /// The first ayah of a page, from the bundled page metadata.
    private func startRef(for page: Int) -> AyahRef? {
        guard data.pageStarts.indices.contains(page - 1) else { return nil }
        return data.pageStarts[page - 1]
    }

    /// "Starts at Al-Baqara 2:77".
    private func startLine(for page: Int) -> String? {
        guard let ref = startRef(for: page) else { return nil }
        let name = data.sura(ref.sura)?.transliteratedName ?? "Surah \(ref.sura)"
        return "Starts at \(name) \(ref.sura):\(ref.aya)"
    }

    private func open(page: Int) {
        guard let ref = startRef(for: page) else { return }
        onOpen(QuranReaderTarget(sura: ref.sura, aya: ref.aya))
    }
}

/// One line for the Learn tab: "Today: pages 12 to 31" or "Make a reading plan".
@MainActor
struct ReadingPlanSummary: View {
    @ObservedObject private var store: ReadingPlanStore
    @Environment(\.appClock) private var clock

    init() {
        _store = ObservedObject(wrappedValue: ReadingPlanStore.shared)
    }

    var body: some View {
        Text(verbatim: ReadingPlanText.summary(plan: store.plan, today: clock.now(), calendar: .current))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MorePalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("readingPlanSummary")
    }
}

/// Pages read out of 604, as a thin ring. Moves only when motion is on.
private struct ReadingPlanRing: View {
    let pagesRead: Int

    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        let fraction = ReadingPlanMath.fraction(nextPage: pagesRead + 1)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 9)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(MorePalette.goldGradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(motionEnabled ? .easeOut(duration: 0.6) : nil, value: pagesRead)
            VStack(spacing: 0) {
                Text(verbatim: String(pagesRead))
                    .font(.title2.weight(.black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: "of \(ReadingPlanMath.pageCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pages read")
        .accessibilityValue(Text(verbatim: "\(pagesRead) of \(ReadingPlanMath.pageCount)"))
        .accessibilityIdentifier("planRing")
    }
}

private struct ReadingPlanChoiceLabel: View {
    let title: String
    let detail: String
    let symbol: String
    /// The pace choice sits inside a card of its own with its picker, so it draws no glass.
    var hasGlass = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline.weight(.heavy))
                Text(verbatim: detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background {
            if hasGlass {
                Color.clear.moreGlass(.light, cornerRadius: 22)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ReadingPlanButtonFill: View {
    let filled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if filled {
            shape.fill(MorePalette.goldGradient)
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}
