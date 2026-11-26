import SwiftUI

/// The Today tab: living sky, next prayer with a live countdown, and the five prayer tiles.
struct TodayView: View {
    @ObservedObject var location: LocationProvider
    let service: PrayerTimesService
    let requestsLocation: Bool

    @Environment(\.appClock) private var clock

    var body: some View {
        TimelineView(.periodic(from: clock.now(), by: 30)) { _ in
            TodayScreen(now: clock.now(), coordinate: location.coordinate, service: service)
        }
        .onAppear {
            if requestsLocation {
                location.start()
            }
        }
    }
}

private struct TodayScreen: View {
    let now: Date
    let coordinate: Coordinate?
    let service: PrayerTimesService

    @State private var prayed: Set<Prayer> = []
    private let store = PrayedStore()

    var body: some View {
        if let day = service.prayerDay(at: coordinate ?? .makkah, on: now) {
            content(for: day)
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

    private func content(for day: PrayerDay) -> some View {
        let next = day.nextPrayer(after: now)
        return ZStack {
            SkyView(phase: day.skyPhase(at: now))
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                NextPrayerView(next: next, now: now)
                    .padding(.top, 28)
                    .padding(.horizontal, 16)
                Spacer(minLength: 16)
                tiles(for: day, next: next.prayer)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
            }
            .foregroundStyle(.white)
        }
        .task(id: store.dayKey(for: now)) {
            prayed = store.prayers(on: now)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(now.formatted(Self.dateStyle))
                .font(.headline.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(locationText)
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .accessibilityIdentifier("locationPill")
        }
    }

    private var locationText: String {
        coordinate == nil ? "Makkah (set your location)" : "Current location"
    }

    private func tiles(for day: PrayerDay, next: Prayer) -> some View {
        HStack(spacing: 8) {
            ForEach(Prayer.allCases) { prayer in
                PrayerTile(
                    prayer: prayer,
                    time: day.time(of: prayer),
                    isNext: prayer == next,
                    isPrayed: prayed.contains(prayer),
                    toggle: { toggle(prayer) }
                )
            }
        }
    }

    private func toggle(_ prayer: Prayer) {
        store.setPrayed(!prayed.contains(prayer), prayer, on: now)
        prayed = store.prayers(on: now)
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

    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 118

    var body: some View {
        VStack(spacing: 2) {
            Text("NEXT PRAYER")
                .font(.caption.weight(.heavy))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.85))
            Text(next.prayer.displayName)
                .font(.system(size: nameSize, weight: .black))
                .kerning(-4)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: Color(hex: 0x071433, opacity: 0.5), radius: 20, y: 10)
                .accessibilityIdentifier("nextPrayerName")
            Text(next.time.formatted(date: .omitted, time: .shortened))
                .font(.title2.weight(.bold))
                .shadow(color: Color(hex: 0x071433, opacity: 0.6), radius: 7, y: 2)
            Text(Self.countdown(from: now, to: next.time))
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .background(Capsule().fill(Color(hex: 0x120B1F, opacity: 0.55)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
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
    let time: Date
    let isNext: Bool
    let isPrayed: Bool
    let toggle: () -> Void

    private static let ink = Color(hex: 0x120B1F)
    private static let mint = Color(hex: 0x8FF0C8)
    private static let shortTime = Date.FormatStyle.dateTime
        .hour(.defaultDigits(amPM: .omitted))
        .minute()

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 7) {
                Text(prayer.displayName)
                    .font(.caption.weight(.bold))
                Text(time.formatted(Self.shortTime))
                    .font(.headline.weight(.heavy))
                checkCircle
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isNext ? Self.ink : Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(tileBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(isNext ? Color.white : Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: isNext ? Color(hex: 0xFBC56A, opacity: 0.45) : .clear, radius: 18, y: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityValue(Text(time.formatted(date: .omitted, time: .shortened)))
        .accessibilityIdentifier("tile-\(prayer.rawValue)")
    }

    private var accessibilityText: String {
        let verb = isPrayed ? "Unmark" : "Mark"
        return "\(verb) \(prayer.displayName) as prayed"
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
            }
        }
        .frame(width: 22, height: 22)
    }
}
