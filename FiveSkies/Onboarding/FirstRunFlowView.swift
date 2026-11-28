import CoreLocation
import SwiftUI
import UserNotifications

/// The first-run flow: welcome, location, alerts, done. Each page has its own sky and the
/// pages cross-fade (only while motion is on). Skip on every page ends the flow.
/// The welcome page carries the one optional "New to Islam" switch (plan N1).
/// Permissions are asked only when the user taps the gold button on that page, and never
/// when `gate.requestsPermissions` is false (screenshot mode).
struct FirstRunFlowView: View {
    @ObservedObject var location: LocationProvider
    let gate: OnboardingGate
    let finish: () -> Void

    @State private var page: OnboardingPage = .welcome
    /// True between tapping "Allow location" and the user answering the system prompt.
    @State private var awaitsLocationAnswer = false
    /// True between tapping "Allow alerts" and the user answering the system prompt.
    @State private var awaitsAlertsAnswer = false
    /// Holds the switch in screenshot mode, where nothing is written to settings.
    @State private var screenshotNewToIslam = false

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.motionEnabled) private var motionEnabled

    private static let ink = Color(hex: 0x120B1F)
    private static let gold = Color(hex: 0xFBC56A)
    private static let goldLight = Color(hex: 0xFFF1C9)

    // Written out because the private @State above would make the memberwise init private.
    init(location: LocationProvider, gate: OnboardingGate, finish: @escaping () -> Void) {
        _location = ObservedObject(wrappedValue: location)
        self.gate = gate
        self.finish = finish
    }

    var body: some View {
        ZStack {
            ZStack {
                OnboardingSky(phase: page.sky)
                    .id(page)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    skipButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                ZStack {
                    OnboardingPageText(page: page)
                        .id(page)
                        .transition(.opacity)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                if page == .welcome {
                    newToIslamCard
                        .padding(.horizontal, 24)
                        .padding(.top, 22)
                        .transition(.opacity)
                }
                Spacer(minLength: 24)
                OnboardingPageDots(current: page)
                    .padding(.bottom, 20)
                primaryButton
                    .padding(.horizontal, 24)
                secondaryButton
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: location.authorizationStatus) { _, status in
            guard awaitsLocationAnswer, status != .notDetermined else { return }
            awaitsLocationAnswer = false
            if page == .location {
                advance()
            }
        }
    }

    // MARK: - Controls

    /// Plan N1: one optional switch, off by default. No other questions.
    private var newToIslamCard: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("I am new to Islam or new to prayer")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("I am new to Islam or new to prayer", isOn: newToIslamBinding)
                    .labelsHidden()
                    .tint(Self.gold)
                    .accessibilityIdentifier("firstRunNewToIslam")
            }
            Text("We will explain terms and keep things simple. You can change this in Settings.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Self.ink.opacity(0.45)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }

    /// Writes to settings, except in screenshot mode, which leaves no trace.
    private var newToIslamBinding: Binding<Bool> {
        Binding(
            get: { gate.recordsCompletion ? settings.newToIslam : screenshotNewToIslam },
            set: { isOn in
                if gate.recordsCompletion {
                    settings.newToIslam = isOn
                } else {
                    screenshotNewToIslam = isOn
                }
            }
        )
    }

    private var skipButton: some View {
        Button(action: finish) {
            Text("Skip")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Capsule().fill(Self.ink.opacity(0.45)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityHint(Text("Closes the introduction and opens Today"))
        .accessibilityIdentifier("onboardingSkip")
    }

    private var primaryButton: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return Button(action: primaryTapped) {
            Text(primaryTitle)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Self.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [Self.goldLight, Self.gold],
                            startPoint: UnitPoint(x: 0.33, y: 0),
                            endPoint: UnitPoint(x: 0.67, y: 1)
                        )
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color(hex: 0xFBC56A, opacity: 0.45), radius: 15, y: 10)
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.97))
        .accessibilityIdentifier(page.primaryIdentifier)
    }

    /// "Not now" on the pages that ask for something. The space is kept on the other pages
    /// so the gold button stays in the same place.
    private var secondaryButton: some View {
        let title = page.secondaryTitle
        return Button {
            advance()
        } label: {
            Text(title ?? "Not now")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .opacity(title == nil ? 0 : 1)
        .disabled(title == nil)
        .accessibilityHidden(title == nil)
        .accessibilityIdentifier("onboardingNotNow")
    }

    private var primaryTitle: String {
        // Once location is decided there is nothing to ask, so the button just moves on.
        if page == .location, gate.requestsPermissions, location.authorizationStatus != .notDetermined {
            return "Continue"
        }
        return page.primaryTitle
    }

    /// Swipe left for the next page, right for the one before. Never asks for a permission.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) else { return }
                if dx < 0, let next = page.next {
                    go(to: next)
                } else if dx > 0, let previous = page.previous {
                    go(to: previous)
                }
            }
    }

    // MARK: - Actions

    private func primaryTapped() {
        switch page {
        case .welcome:
            advance()
        case .location:
            allowLocation()
        case .alerts:
            allowAlerts()
        case .done:
            finish()
        }
    }

    /// Asks through the shared LocationProvider, then moves on once the user answers.
    private func allowLocation() {
        guard gate.requestsPermissions,
              !awaitsLocationAnswer,
              location.authorizationStatus == .notDetermined else {
            advance()
            return
        }
        awaitsLocationAnswer = true
        location.requestAgain()
    }

    /// Asks for alert and sound permission, then moves on once the user answers.
    private func allowAlerts() {
        guard gate.requestsPermissions else {
            advance()
            return
        }
        guard !awaitsAlertsAnswer else { return }
        awaitsAlertsAnswer = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                self.awaitsAlertsAnswer = false
                if self.page == .alerts {
                    self.advance()
                }
            }
        }
    }

    private func advance() {
        guard let next = page.next else {
            finish()
            return
        }
        go(to: next)
    }

    private func go(to target: OnboardingPage) {
        awaitsLocationAnswer = false
        withAnimation(motionEnabled ? .easeInOut(duration: 0.7) : nil) {
            page = target
        }
    }
}

/// The sky behind one page, with soft darkening at the top for the words and at the
/// bottom for the buttons.
private struct OnboardingSky: View {
    let phase: Prayer

    var body: some View {
        ZStack {
            SkyView(phase: phase, showsCelestial: true)
            SkyLegibilityScrim(phase: phase)
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color(hex: 0x061230, opacity: 0.28), location: 0),
                    Gradient.Stop(color: Color(hex: 0x061230, opacity: 0), location: 0.45),
                    Gradient.Stop(color: Color(hex: 0x120B1F, opacity: 0), location: 0.6),
                    Gradient.Stop(color: Color(hex: 0x120B1F, opacity: 0.55), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The symbol, large heavy title and short message of one page.
private struct OnboardingPageText: View {
    let page: OnboardingPage

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: page.symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFD27A))
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 8, y: 2)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.system(size: titleSize, weight: .black))
                .kerning(-1)
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 20, y: 10)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(page.titleIdentifier)
            Text(page.message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))
                .minimumScaleFactor(0.7)
                .shadow(color: Color(hex: 0x071433, opacity: 0.6), radius: 7, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Four dots, the current one a wider gold bar.
private struct OnboardingPageDots: View {
    let current: OnboardingPage

    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases) { page in
                Capsule()
                    .fill(page == current ? Color(hex: 0xFBC56A) : Color.white.opacity(0.45))
                    .frame(width: page == current ? 24 : 8, height: 8)
            }
        }
        .animation(motionEnabled ? .easeInOut(duration: 0.4) : nil, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current.number) of \(OnboardingPage.allCases.count)"))
        .accessibilityIdentifier("onboardingDots")
    }
}

/// Presents the first-run flow over the app at launch when the gate says so, and records
/// it as completed when the user finishes or skips.
struct FirstRunFlowModifier: ViewModifier {
    let location: LocationProvider
    let defaults: UserDefaults
    let onFinish: () -> Void

    @State private var gate: OnboardingGate
    @State private var isPresented: Bool

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.motionEnabled) private var motionEnabled

    init(
        location: LocationProvider,
        gate: OnboardingGate = .live(),
        defaults: UserDefaults = .standard,
        onFinish: @escaping () -> Void
    ) {
        self.location = location
        self.defaults = defaults
        self.onFinish = onFinish
        _gate = State(initialValue: gate)
        _isPresented = State(initialValue: gate.shouldShow)
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                FirstRunFlowView(location: location, gate: gate, finish: finish)
                    .environmentObject(settings)
            }
    }

    private func finish() {
        guard isPresented else { return }
        if gate.recordsCompletion {
            OnboardingGate.markCompleted(in: defaults)
        }
        var transaction = Transaction()
        transaction.disablesAnimations = !motionEnabled
        withTransaction(transaction) {
            isPresented = false
        }
        onFinish()
    }
}

extension View {
    /// Shows the first-run flow once, at launch. `onFinish` runs when it is finished or skipped.
    func firstRunFlow(location: LocationProvider, onFinish: @escaping () -> Void = {}) -> some View {
        modifier(FirstRunFlowModifier(location: location, onFinish: onFinish))
    }
}
