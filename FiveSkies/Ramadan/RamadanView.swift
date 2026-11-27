import SwiftUI

/// Ramadan: today's Suhoor and Iftar times with a countdown, the Hijri day, a fasting log
/// and a Taraweeh mark for tonight.
struct RamadanView: View {
    // The Today tab's LocationProvider is not shared, so this screen owns its own instance,
    // started the same way as the Qibla tab's.
    @StateObject private var location: LocationProvider

    @Environment(\.appClock) private var clock
    @EnvironmentObject private var settings: AppSettings

    private let launch: LaunchOptions
    private let service: PrayerTimesService
    private let store: FastingLogStore

    init() {
        self.init(store: FastingLogStore())
    }

    init(store: FastingLogStore) {
        launch = LaunchOptions()
        service = PrayerTimesService()
        self.store = store
        _location = StateObject(wrappedValue: LocationProvider())
    }

    var body: some View {
        let configured = service.applying(method: settings.calculationMethod, asrRule: settings.asrRule)
        return TimelineView(.periodic(from: clock.now(), by: 30)) { _ in
            RamadanScreen(
                now: clock.now(),
                place: place,
                service: configured,
                store: store,
                pillOpensSettings: launch.requestsLocation && location.isDenied,
                requestLocation: requestLocation
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if launch.requestsLocation {
                location.start()
            }
        }
    }

    /// Same rules as the Qibla tab: the fixed phase mode always uses the Makkah fallback,
    /// and with no location the labelled fallback is used, in Makkah's own time zone.
    private var place: Place {
        if launch.fixedPhase != nil {
            return Place.makkahFallback
        }
        if let coordinate = location.coordinate {
            return Place.device(coordinate)
        }
        return Place.makkahFallback
    }

    private func requestLocation() {
        guard launch.requestsLocation else { return }
        location.requestAgain()
    }
}

enum RamadanPalette {
    static let sky = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(hex: 0x071433), location: 0),
            Gradient.Stop(color: Color(hex: 0x2B2A7A), location: 0.35),
            Gradient.Stop(color: Color(hex: 0x7A4E8F), location: 0.72),
            Gradient.Stop(color: Color(hex: 0x2A1638), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

private struct RamadanScreen: View {
    let now: Date
    let place: Place
    let service: PrayerTimesService
    let store: FastingLogStore
    let pillOpensSettings: Bool
    let requestLocation: () -> Void

    @State private var fastedDays: Set<Int> = []
    @State private var voluntaryCount = 0
    @State private var loggedToday = false
    @State private var taraweeh = false
    @State private var revealed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private var ramadan: RamadanCalendar {
        RamadanCalendar(timeZone: place.timeZone)
    }

    private var today: HijriDay? {
        ramadan.hijriDay(for: now)
    }

    var body: some View {
        let calendar = ramadan
        let dayOfRamadan = calendar.dayOfRamadan(on: now)
        let logYear = calendar.logYear(for: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusCard(calendar: calendar, dayOfRamadan: dayOfRamadan)
                    .riseIn(revealed: revealed, delay: 0)
                timesSection
                    .riseIn(revealed: revealed, delay: 0.06)
                if let logYear {
                    fastingLog(year: logYear, today: dayOfRamadan)
                        .riseIn(revealed: revealed, delay: 0.12)
                }
                if dayOfRamadan == nil {
                    voluntaryCard
                        .riseIn(revealed: revealed, delay: 0.16)
                }
                taraweehCard
                    .riseIn(revealed: revealed, delay: 0.2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(RamadanPalette.sky.ignoresSafeArea())
        .onAppear {
            revealed = true
            reload()
        }
        .onChange(of: today?.key) { _, _ in
            reload()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            MoreScreenTitle(text: "Ramadan", identifier: "ramadanTitle")
            LocationPill(
                text: place.isFallback ? LocationPillText.fallback : LocationPillText.current,
                opensSettings: pillOpensSettings,
                identifier: "ramadanLocationPill",
                request: requestLocation
            )
        }
    }

    // MARK: - Status

    private func statusCard(calendar: RamadanCalendar, dayOfRamadan: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MoreCaption(text: calendar.hijriDateText(for: now))
                .accessibilityIdentifier("ramadanHijriDate")
            Group {
                if let dayOfRamadan {
                    Text("Day \(dayOfRamadan) of Ramadan")
                } else if let upcoming = calendar.nextRamadan(after: now) {
                    Text(verbatim: Self.beginsText(daysAway: upcoming.daysAway))
                } else {
                    Text("Ramadan")
                }
            }
            .font(.title2.weight(.heavy))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ramadanDayStatus")
            Text("Based on the Umm al-Qura calendar. The start can differ by a day with local moon sighting.")
                .font(.caption.weight(.medium))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.light, cornerRadius: 24)
        .accessibilityElement(children: .combine)
    }

    static func beginsText(daysAway: Int) -> String {
        daysAway == 1 ? "Ramadan begins in about 1 day" : "Ramadan begins in about \(daysAway) days"
    }

    // MARK: - Times

    @ViewBuilder
    private var timesSection: some View {
        if let day = service.prayerDay(for: place, on: now) {
            let target = RamadanTimes.next(after: now, in: day)
            let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.timeZone)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    timeTile(
                        title: RamadanMoment.suhoorEnds.title,
                        time: day.fajr.formatted(style),
                        highlighted: target.moment == .suhoorEnds,
                        identifier: "suhoorTime"
                    )
                    timeTile(
                        title: RamadanMoment.iftar.title,
                        time: day.maghrib.formatted(style),
                        highlighted: target.moment == .iftar,
                        identifier: "iftarTime"
                    )
                }
                Text("\(target.moment.title) in \(RamadanTimes.countdown(from: now, to: target.time))")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(MorePalette.ink.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .accessibilityIdentifier("ramadanCountdown")
            }
        } else {
            Text("Prayer times are not available for this location.")
                .font(.headline)
                .padding(16)
                .frame(maxWidth: .infinity)
                .moreGlass(.dark, cornerRadius: 24)
        }
    }

    private func timeTile(title: String, time: String, highlighted: Bool, identifier: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.heavy))
            Text(time)
                .font(.title2.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(highlighted ? MorePalette.ink : Color.white)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(tileBackground(highlighted: highlighted))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func tileBackground(highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if highlighted {
            shape.fill(MorePalette.goldGradient)
                .overlay(shape.strokeBorder(Color.white, lineWidth: 1))
        } else {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        }
    }

    // MARK: - Fasting log

    private func fastingLog(year: Int, today dayOfRamadan: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fasting log")
                        .font(.headline.weight(.heavy))
                    Text("Ramadan \(String(year)) AH")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
                Spacer(minLength: 8)
                Text("\(fastedDays.count) of \(RamadanCalendar.logDayCount) marked")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.mint)
                    .accessibilityIdentifier("fastCount")
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...RamadanCalendar.logDayCount, id: \.self) { day in
                    dayCircle(day: day, year: year, isToday: day == dayOfRamadan)
                }
            }
        }
        .padding(16)
        .moreGlass(.dark, cornerRadius: 24)
    }

    private func dayCircle(day: Int, year: Int, isToday: Bool) -> some View {
        let fasted = fastedDays.contains(day)
        return Button {
            store.setFasted(!fasted, day: day, year: year)
            reload()
        } label: {
            ZStack {
                Circle()
                    .fill(fasted ? MorePalette.mint : Color.clear)
                Circle()
                    .strokeBorder(
                        isToday ? MorePalette.gold : (fasted ? MorePalette.mint : Color.white.opacity(0.4)),
                        lineWidth: isToday ? 2.5 : 1.5
                    )
                Text("\(day)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(fasted ? MorePalette.ink : Color.white)
            }
            .frame(width: 40, height: 40)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
        .sensoryFeedback(.selection, trigger: fasted)
        .accessibilityLabel(Text("Day \(day)"))
        .accessibilityValue(Text(fasted ? "Fasted" : "Not marked"))
        .accessibilityAddTraits(fasted ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("fastDay-\(day)")
    }

    // MARK: - Voluntary fasts

    private var voluntaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Voluntary fasts")
                    .font(.headline.weight(.heavy))
                Spacer(minLength: 8)
                Text(verbatim: voluntaryCount == 1 ? "1 logged" : "\(voluntaryCount) logged")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(MorePalette.mint)
                    .accessibilityIdentifier("voluntaryCount")
            }
            Button {
                guard let today else { return }
                store.setVoluntaryFast(!loggedToday, on: today)
                reload()
            } label: {
                Label(
                    loggedToday ? "Logged today. Tap to undo" : "Log a fast today",
                    systemImage: loggedToday ? "checkmark.circle.fill" : "plus.circle"
                )
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(loggedToday ? Color.white : MorePalette.ink)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(voluntaryButtonBackground)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityIdentifier("logVoluntaryFast")
        }
        .padding(16)
        .moreGlass(.dark, cornerRadius: 24)
    }

    @ViewBuilder
    private var voluntaryButtonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if loggedToday {
            shape.fill(Color.white.opacity(0.1))
                .overlay(shape.strokeBorder(MorePalette.mint, lineWidth: 1))
        } else {
            shape.fill(MorePalette.goldGradient)
        }
    }

    // MARK: - Taraweeh

    private var taraweehCard: some View {
        Toggle(isOn: Binding(
            get: { taraweeh },
            set: { value in
                guard let today else { return }
                store.setTaraweeh(value, on: today)
                reload()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Taraweeh tonight")
                    .font(.headline.weight(.heavy))
                Text(taraweeh ? "Marked for tonight" : "Not marked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
            }
        }
        .tint(MorePalette.mint)
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .moreGlass(.light, cornerRadius: 24)
        .accessibilityIdentifier("taraweehToggle")
    }

    // MARK: - Loading

    private func reload() {
        let calendar = ramadan
        if let year = calendar.logYear(for: now) {
            fastedDays = store.fastedDays(inRamadanOf: year)
        } else {
            fastedDays = []
        }
        voluntaryCount = store.voluntaryFastCount
        if let today = calendar.hijriDay(for: now) {
            loggedToday = store.isVoluntaryFastLogged(on: today)
            taraweeh = store.prayedTaraweeh(on: today)
        } else {
            loggedToday = false
            taraweeh = false
        }
    }
}
