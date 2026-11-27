import SwiftUI

/// The Today tab: living sky, next prayer with a live countdown, and the five prayer tiles.
struct TodayView: View {
    @ObservedObject var location: LocationProvider
    let service: PrayerTimesService
    let requestsLocation: Bool

    @Environment(\.appClock) private var clock
    @EnvironmentObject private var settings: AppSettings
    @State private var locatingTimedOut = false

    /// How long to wait for the first fix before showing the Makkah fallback (4 seconds).
    private static let locatingTimeout: UInt64 = 4_000_000_000

    // Written out because the private @State above would make the memberwise init private.
    init(location: LocationProvider, service: PrayerTimesService, requestsLocation: Bool) {
        _location = ObservedObject(wrappedValue: location)
        self.service = service
        self.requestsLocation = requestsLocation
    }

    var body: some View {
        let configured = service.applying(method: settings.calculationMethod, asrRule: settings.asrRule)
        return TimelineView(.periodic(from: clock.now(), by: 30)) { _ in
            TodayScreen(
                now: clock.now(),
                place: place,
                service: configured,
                pillText: pillText,
                pillOpensSettings: requestsLocation && location.isDenied,
                requestLocation: requestLocation
            )
        }
        .onAppear {
            if requestsLocation {
                location.start()
            }
        }
        .task {
            guard requestsLocation, !locatingTimedOut else { return }
            do {
                try await Task.sleep(nanoseconds: Self.locatingTimeout)
            } catch {
                return
            }
            locatingTimedOut = true
        }
    }

    /// Where the times are for, or nil while the first device fix is still expected.
    private var place: Place? {
        if let coordinate = location.coordinate {
            return Place.device(coordinate)
        }
        if requestsLocation && !locatingTimedOut && location.isAwaitingFix {
            return nil
        }
        return Place.makkahFallback
    }

    private var pillText: String {
        guard let place = place else { return LocationPillText.locating }
        return place.isFallback ? LocationPillText.fallback : LocationPillText.current
    }

    private func requestLocation() {
        guard requestsLocation else { return }
        location.requestAgain()
    }
}

private struct TodayScreen: View {
    let now: Date
    /// nil while locating: the layout is shown with placeholder times.
    let place: Place?
    let service: PrayerTimesService
    let pillText: String
    let pillOpensSettings: Bool
    let requestLocation: () -> Void

    @State private var prayed: Set<Prayer> = []
    @State private var showsSettings = false
    @State private var showsDay = false
    /// Turns true on first appearance to play the entrance. With motion off everything is in place anyway.
    @State private var revealed = false
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var signatureStar: SignatureStarController
    private let store = PrayedStore()

    private var isLocating: Bool {
        place == nil
    }

    var body: some View {
        let shown = place ?? Place.makkahFallback
        if let day = service.prayerDay(for: shown, on: now) {
            content(for: day, timeZone: shown.timeZone)
        } else {
            ZStack {
                Color(hex: 0x120B1F).ignoresSafeArea()
                Text("Prayer times are not available for this location.")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private func content(for day: PrayerDay, timeZone: TimeZone) -> some View {
        let next = day.nextPrayer(after: now)
        let format = TileTimeFormat(timeZone: timeZone)
        let phase = day.skyPhase(at: now)
        return ZStack {
            SkyView(phase: phase)
            SkyLegibilityScrim(phase: phase)
            // In the sky, behind the words and tiles.
            SignatureStarOverlay()
            VStack(spacing: 0) {
                header(timeZone: timeZone)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                NextPrayerView(
                    next: next,
                    now: now,
                    currentName: day.currentPeriodName(at: now),
                    timeZone: timeZone,
                    isLocating: isLocating,
                    revealed: revealed
                )
                .padding(.top, 12)
                .padding(.horizontal, 16)
                Spacer(minLength: 16)
                TrackerChipsView(now: now)
                    .padding(.bottom, 10)
                    .riseIn(revealed: revealed, delay: 0.28)
                tiles(for: day, next: next.prayer, format: format, timeZone: timeZone)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
            .foregroundStyle(.white)
        }
        .onAppear {
            revealed = true
        }
        .onChange(of: phaseSample(phase), initial: true) { _, sample in
            if let sample = sample {
                signatureStar.observe(sample)
            }
        }
        .task(id: store.dayKey(for: now)) {
            prayed = store.prayers(on: now)
        }
        .task(id: scheduleKey(for: day)) {
            // Nothing is scheduled for the fallback's times while the real location may still arrive.
            guard let place = place else { return }
            scheduler.reschedule(
                service: service,
                place: place,
                preferences: settings.alertPreferences,
                now: now
            )
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(scheduler)
        }
        .sheet(isPresented: $showsDay) {
            DayView(service: service, place: place ?? Place.makkahFallback)
                .environmentObject(settings)
        }
    }

    /// The sky phase with what it was worked out for, or nil while locating.
    private func phaseSample(_ phase: Prayer) -> SkyPhaseSample? {
        guard let place = place else { return nil }
        let location = place.isFallback
            ? "fallback"
            : String(format: "%.2f,%.2f", place.coordinate.latitude, place.coordinate.longitude)
        let context = [location, String(describing: settings.calculationMethod), String(describing: settings.asrRule)]
            .joined(separator: "|")
        return SkyPhaseSample(phase: phase, context: context)
    }

    /// Changes when a new day's times are computed (new day, location, method or Asr rule)
    /// and when locating ends.
    private func scheduleKey(for day: PrayerDay) -> String {
        let times = [day.fajr, day.asr, day.isha].map { String(Int($0.timeIntervalSince1970)) }
        let state: String
        if let place = place {
            state = place.isFallback ? "fallback" : "device"
        } else {
            state = "locating"
        }
        return ([store.dayKey(for: now), state] + times).joined(separator: "|")
    }

    private func header(timeZone: TimeZone) -> some View {
        var dateStyle = Self.dateStyle
        dateStyle.timeZone = timeZone
        return HStack(alignment: .center, spacing: 10) {
            Button {
                showsDay = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(now.formatted(dateStyle))
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.heavy))
                        .opacity(0.7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.96))
            .accessibilityHint(Text("Shows the full day"))
            .accessibilityIdentifier("openDayView")
            .layoutPriority(0)
            Spacer(minLength: 4)
            LocationPill(
                text: pillText,
                opensSettings: pillOpensSettings,
                identifier: "locationPill",
                request: requestLocation
            )
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
            .sensoryFeedback(trigger: showsSettings) { _, opened in
                opened ? .impact(weight: .light) : nil
            }
            .accessibilityLabel("Settings")
        }
    }

    private func tiles(for day: PrayerDay, next: Prayer, format: TileTimeFormat, timeZone: TimeZone) -> some View {
        let spoken = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        return HStack(spacing: 8) {
            ForEach(Array(Prayer.allCases.enumerated()), id: \.element) { index, prayer in
                let time = day.time(of: prayer)
                PrayerTile(
                    prayer: prayer,
                    timeText: isLocating ? "--:--" : format.time(time),
                    periodText: isLocating ? nil : format.period(time),
                    spokenTime: isLocating ? "Not known yet" : time.formatted(spoken),
                    isNext: !isLocating && prayer == next,
                    isPrayed: prayed.contains(prayer),
                    toggle: { toggle(prayer) }
                )
                .riseIn(revealed: revealed, delay: 0.3 + 0.07 * Double(index), distance: 44)
            }
        }
    }

    private func toggle(_ prayer: Prayer) {
        let marking = !prayed.contains(prayer)
        store.setPrayed(marking, prayer, on: now)
        prayed = store.prayers(on: now)
        if marking {
            signatureStar.prayerMarked()
        }
    }

    private static let dateStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.calendar = Calendar(identifier: .gregorian)
        return style
    }()
}

private struct NextPrayerView: View {
    let next: UpcomingPrayer
    let now: Date
    /// The current period, such as "Fajr" or "Morning", for the "Now:" line.
    let currentName: String
    let timeZone: TimeZone
    let isLocating: Bool
    /// Drives the staggered entrance of the headline block.
    let revealed: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 118
    @Environment(\.motionEnabled) private var motionEnabled

    /// Entrance delay for the headline element at `step`, about 0.08 seconds apart.
    private func delay(_ step: Int) -> Double {
        0.08 * Double(step)
    }

    var body: some View {
        let name = isLocating ? "--" : next.prayer.displayName
        let countdown = isLocating ? "--" : Self.countdown(from: now, to: next.time)
        return VStack(spacing: 2) {
            Text("Now: \(currentName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.bottom, 6)
                .opacity(isLocating ? 0 : 1)
                .accessibilityHidden(isLocating)
                .accessibilityIdentifier("currentPeriod")
                .riseIn(revealed: revealed, delay: delay(0))
            Text("NEXT PRAYER")
                .font(.caption.weight(.heavy))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: Color(hex: 0x071433, opacity: 0.35), radius: 4, y: 1)
                .riseIn(revealed: revealed, delay: delay(1))
            Text(name)
                .font(.system(size: nameSize, weight: .black))
                .kerning(-4)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.opacity)
                .animation(motionEnabled ? .easeInOut(duration: 0.6) : nil, value: name)
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 20, y: 10)
                .accessibilityIdentifier("nextPrayerName")
                .riseIn(revealed: revealed, delay: delay(2))
            Text(isLocating ? "--:--" : next.time.formatted(timeStyle))
                .font(.title2.weight(.bold))
                .shadow(color: Color(hex: 0x071433, opacity: 0.6), radius: 7, y: 2)
                .riseIn(revealed: revealed, delay: delay(3))
            Text(countdown)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(motionEnabled ? .easeInOut(duration: 0.4) : nil, value: countdown)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .background(Capsule().fill(Color(hex: 0x120B1F, opacity: 0.55)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .padding(.top, 12)
                .riseIn(revealed: revealed, delay: delay(4))
        }
        .multilineTextAlignment(.center)
    }

    /// The headline time with AM or PM where the locale uses them, in the place's time zone.
    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
    }

    /// "in 1h 12m" style countdown, rounded up to the next whole minute.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "in \(hours)h \(remainder)m" : "in \(remainder)m"
    }
}

private struct PrayerTile: View {
    let prayer: Prayer
    let timeText: String
    /// "AM" or "PM" under the time in 12-hour locales, nil otherwise.
    let periodText: String?
    let spokenTime: String
    let isNext: Bool
    let isPrayed: Bool
    let toggle: () -> Void

    private static let ink = Color(hex: 0x120B1F)
    private static let mint = Color(hex: 0x8FF0C8)

    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 7) {
                Text(prayer.displayName)
                    .font(.caption.weight(.bold))
                VStack(spacing: 0) {
                    Text(timeText)
                        .font(.headline.weight(.heavy))
                    if let periodText = periodText {
                        Text(periodText)
                            .font(.caption2.weight(.semibold))
                            .opacity(0.75)
                    }
                }
                checkCircle
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isNext ? Self.ink : Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(tileBackground)
            .overlay(tileEdge)
            .modifier(NextTileGlow(isNext: isNext))
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.96))
        .sensoryFeedback(trigger: isPrayed) { _, prayed in
            prayed ? .success : .selection
        }
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityValue(Text(spokenTime))
        .accessibilityIdentifier("tile-\(prayer.rawValue)")
    }

    private var accessibilityText: String {
        let verb = isPrayed ? "Unmark" : "Mark"
        return "\(verb) \(prayer.displayName) as prayed"
    }

    /// A lit top edge fading down the sides, so each tile reads as a pane of glass.
    private var tileEdge: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: isNext
                        ? [Color.white, Color.white.opacity(0.7)]
                        : [Color.white.opacity(0.45), Color.white.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if isNext {
            shape.fill(
                LinearGradient(
                    colors: [Color(hex: 0xFFF1C9), Color(hex: 0xFBC56A)],
                    startPoint: UnitPoint(x: 0.33, y: 0),
                    endPoint: UnitPoint(x: 0.67, y: 1)
                )
            )
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.white.opacity(0.1)))
        }
    }

    private var checkCircle: some View {
        let ring: Color = isPrayed ? Self.mint : (isNext ? Self.ink : Color.white.opacity(0.5))
        return ZStack {
            Circle()
                .fill(isPrayed ? Self.mint : Color.clear)
            Circle()
                .strokeBorder(ring, lineWidth: 2)
            if isPrayed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Self.ink)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
        .animation(motionEnabled ? .spring(response: 0.3, dampingFraction: 0.7) : nil, value: isPrayed)
    }
}

/// The gold shadow under the next prayer's tile. While ambient motion is on it glows
/// slowly brighter and softer over 4 seconds; at rest it is the plain mockup shadow.
private struct NextTileGlow: ViewModifier {
    let isNext: Bool

    @Environment(\.ambientMotionEnabled) private var animates

    func body(content: Content) -> some View {
        let pulses = isNext && animates
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !pulses)) { context in
            let wave = pulses ? MotionWave.breath(context.date.timeIntervalSinceReferenceDate, period: 4) : 0.5
            content
                .shadow(
                    color: isNext ? Color(hex: 0xFBC56A, opacity: 0.3 + 0.3 * wave) : .clear,
                    radius: 15 + 6 * CGFloat(wave),
                    y: 14
                )
        }
    }
}
