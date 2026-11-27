import SwiftUI

// Plain SwiftUI views for the widgets, compiled into the app and the widget extension.
// Nothing here uses WidgetKit, so the app's debug widget gallery can draw the same views.
// The extension wraps them and supplies the container background separately.

/// How the countdown is drawn. Widgets use `.live`, a system timer that ticks without new
/// entries. The gallery uses `.frozen`, worked out from the entry's own date, so screenshots are stable.
enum WidgetCountdownMode {
    case live
    case frozen
}

/// Text helpers shared by every widget.
enum PrayerWidgetText {
    /// "2:13 PM" in 12-hour locales or "14:13" in 24-hour ones, in the place's time zone,
    /// using the same rules as the Today tiles.
    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let format = TileTimeFormat(timeZone: timeZone)
        if let period = format.period(date) {
            return "\(format.time(date)) \(period)"
        }
        return format.time(date)
    }

    /// "in 1h 12m" style countdown, rounded up to the next whole minute.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "in \(hours)h \(remainder)m" : "in \(remainder)m"
    }

    /// A short name that fits inside the circular lock screen widget.
    static func abbreviation(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr: return "Fajr"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Mgrb"
        case .isha: return "Isha"
        }
    }

    /// "5:34" or "17:34" with no AM or PM, for the tight lock screen list.
    static func compactTime(_ date: Date, timeZone: TimeZone) -> String {
        TileTimeFormat(timeZone: timeZone).time(date)
    }

    /// "until 6:52 AM", the end of a prayer's window.
    static func until(_ end: Date, timeZone: TimeZone) -> String {
        "until \(time(end, timeZone: timeZone))"
    }

    /// "Asr at 3:15 PM", for the inline lock screen widget.
    static func inline(_ entry: PrayerWidgetEntry) -> String {
        "\(entry.next.prayer.displayName) at \(time(entry.next.time, timeZone: entry.timeZone))"
    }
}

/// Shared colors.
enum PrayerWidgetPalette {
    static let ink = Color(hex: 0x120B1F)
    static let lamp = Color(hex: 0xFFD27A)
    static let gold = LinearGradient(
        colors: [Color(hex: 0xFFF1C9), Color(hex: 0xFBC56A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let night = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(hex: 0x03061A), location: 0),
            Gradient.Stop(color: Color(hex: 0x0A1036), location: 0.45),
            Gradient.Stop(color: Color(hex: 0x141E55), location: 0.8),
            Gradient.Stop(color: Color(hex: 0x2E2560), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let textShadow = Color(hex: 0x071433, opacity: 0.5)
}

/// The countdown to the next prayer, live or frozen.
struct WidgetCountdownText: View {
    let entry: PrayerWidgetEntry
    let mode: WidgetCountdownMode

    var body: some View {
        switch mode {
        case .live:
            (Text("in ") + Text(timerInterval: liveInterval, countsDown: true))
                .monospacedDigit()
                .multilineTextAlignment(.center)
        case .frozen:
            Text(PrayerWidgetText.countdown(from: entry.date, to: entry.next.time))
        }
    }

    /// From the entry's date to the next prayer. The lower bound never passes the upper one.
    private var liveInterval: ClosedRange<Date> {
        min(entry.date, entry.next.time)...entry.next.time
    }
}

/// Marks for one prayer in a list: the current one is filled gold, the next one is outlined.
private struct PrayerRowMarks {
    let isCurrent: Bool
    let isNext: Bool

    init(row: PrayerWidgetRow, entry: PrayerWidgetEntry) {
        isCurrent = row.prayer == entry.current
        // Compared by time, so tomorrow's Fajr does not mark this morning's row.
        isNext = !isCurrent && row.time == entry.next.time
    }
}

/// A small, still version of the sky for one phase: the gradient, a few stars at night,
/// and the mosque skyline with its top at `skylineTop` (a fraction of the height).
struct WidgetSkyBackground: View {
    let phase: Prayer
    let skylineTop: CGFloat

    /// Fixed star positions as fractions of width and height.
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.62, 0.08, 1.6), (0.78, 0.16, 1.2), (0.9, 0.06, 1.4), (0.7, 0.3, 1.0),
        (0.86, 0.38, 1.3), (0.55, 0.2, 1.0), (0.95, 0.26, 1.1), (0.48, 0.05, 1.2)
    ]

    var body: some View {
        let style = SkyStyle.style(for: phase)
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: style.skyStops, startPoint: .top, endPoint: .bottom)
                if let starOpacity = style.starOpacities.first, starOpacity > 0 {
                    ForEach(0..<Self.stars.count, id: \.self) { index in
                        let star = Self.stars[index]
                        Circle()
                            .fill(Color.white.opacity(0.85 * starOpacity))
                            .frame(width: star.2 * 2, height: star.2 * 2)
                            .position(x: star.0 * width, y: star.1 * height)
                    }
                }
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: height * skylineTop)
                    ZStack {
                        HillShape()
                            .fill(style.hill)
                            .opacity(style.hillOpacity)
                        MosqueSkylineShape()
                            .fill(style.land)
                        SkylineLightsShape()
                            .fill(PrayerWidgetPalette.lamp)
                            .opacity(style.lightsOpacity)
                        GroundShape()
                            .fill(style.ground)
                    }
                    .frame(width: width, height: width * 250 / 390)
                    style.ground
                }
                .frame(width: width, height: height, alignment: .top)
            }
            .frame(width: width, height: height)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// "NEXT", the prayer name large and heavy, its time, and the countdown pill.
struct NextPrayerBlock: View {
    let entry: PrayerWidgetEntry
    let countdown: WidgetCountdownMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NEXT")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.85))
            Text(entry.next.prayer.displayName)
                .font(.system(size: 44, weight: .black))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(PrayerWidgetText.time(entry.next.time, timeZone: entry.timeZone))
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 2)
            WidgetCountdownText(entry: entry, mode: countdown)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(PrayerWidgetPalette.ink.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .shadow(color: PrayerWidgetPalette.textShadow, radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// "Next prayer" (systemSmall).
struct SmallPrayerWidgetView: View {
    let entry: PrayerWidgetEntry
    var countdown: WidgetCountdownMode = .live
    /// False in the widget extension, which passes `background` to the container instead.
    var drawsBackground = true

    static func background(for entry: PrayerWidgetEntry) -> some View {
        WidgetSkyBackground(phase: entry.phase, skylineTop: 0.59)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if drawsBackground {
                Self.background(for: entry)
            }
            NextPrayerBlock(entry: entry, countdown: countdown)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Today's prayers" (systemMedium): the next prayer on its sky, then five rows with each
/// prayer's start and "until" end, the current one highlighted.
struct MediumPrayerWidgetView: View {
    let entry: PrayerWidgetEntry
    var countdown: WidgetCountdownMode = .live
    var drawsBackground = true

    static var background: some View {
        PrayerWidgetPalette.ink
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                WidgetSkyBackground(phase: entry.phase, skylineTop: 0.7)
                NextPrayerBlock(entry: entry, countdown: countdown)
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .padding(.top, 14)
            }
            .frame(width: 124)
            .frame(maxHeight: .infinity)
            .clipped()

            VStack(spacing: 3) {
                ForEach(entry.rows, id: \.prayer) { row in
                    rowView(for: row)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            if drawsBackground {
                Self.background
            }
        }
    }

    private func rowView(for row: PrayerWidgetRow) -> some View {
        let marks = PrayerRowMarks(row: row, entry: entry)
        return HStack(spacing: 6) {
            Text(row.prayer.displayName)
                .font(.system(size: 12, weight: .bold))
            Spacer(minLength: 2)
            Text(PrayerWidgetText.time(row.time, timeZone: entry.timeZone))
                .font(.system(size: 12, weight: .heavy))
            Text(PrayerWidgetText.until(row.end, timeZone: entry.timeZone))
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.75)
                .frame(width: 72, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(marks.isCurrent ? PrayerWidgetPalette.ink : Color.white)
        .background {
            if marks.isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(PrayerWidgetPalette.gold)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
            }
        }
        .overlay {
            if marks.isNext {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(marks.isCurrent ? Text("Now") : Text(""))
    }
}

/// "Prayers and progress" (systemLarge): the next prayer, progress since the last one,
/// and five rows on a night gradient.
struct LargePrayerWidgetView: View {
    let entry: PrayerWidgetEntry
    var countdown: WidgetCountdownMode = .live
    var drawsBackground = true

    static var background: some View {
        PrayerWidgetPalette.night
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT PRAYER")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.next.prayer.displayName)
                            .font(.system(size: 28, weight: .black))
                            .lineLimit(1)
                        Text(PrayerWidgetText.time(entry.next.time, timeZone: entry.timeZone))
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                WidgetCountdownText(entry: entry, mode: countdown)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            }

            ProgressBar(progress: entry.progress)
                .frame(height: 6)
                .padding(.top, 12)

            Text("Now: \(entry.currentPeriodName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.top, 6)

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .padding(.top, 12)
                .padding(.bottom, 8)

            VStack(spacing: 3) {
                ForEach(entry.rows, id: \.prayer) { row in
                    rowView(for: row)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if drawsBackground {
                Self.background
            }
        }
    }

    private func rowView(for row: PrayerWidgetRow) -> some View {
        let marks = PrayerRowMarks(row: row, entry: entry)
        return HStack(spacing: 8) {
            Text(row.prayer.displayName)
                .font(.system(size: 15, weight: .bold))
            Spacer(minLength: 4)
            Text(PrayerWidgetText.time(row.time, timeZone: entry.timeZone))
                .font(.system(size: 15, weight: .heavy))
            Text(PrayerWidgetText.until(row.end, timeZone: entry.timeZone))
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.75)
                .frame(width: 96, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .foregroundStyle(marks.isCurrent ? PrayerWidgetPalette.ink : Color.white)
        .background {
            if marks.isCurrent {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PrayerWidgetPalette.gold)
            }
        }
        .overlay {
            if marks.isNext {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(marks.isCurrent ? Text("Now") : Text(""))
    }
}

/// A thin rounded bar filled to `progress` in gold.
private struct ProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(PrayerWidgetPalette.gold)
                    .frame(width: max(6, proxy.size.width * CGFloat(progress)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lock screen circle: the next prayer's short name in a ring that fills through the current
/// window, from the previous prayer toward the next.
/// Colors are left to the system so vibrant rendering works.
struct CircularPrayerWidgetView: View {
    let entry: PrayerWidgetEntry

    var body: some View {
        Gauge(value: entry.progress, in: 0...1) {
            Text(entry.next.prayer.displayName)
        } currentValueLabel: {
            Text(PrayerWidgetText.abbreviation(entry.next.prayer))
                .font(.system(size: 14, weight: .heavy))
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(Text("Next prayer \(entry.next.prayer.displayName)"))
    }
}

/// Lock screen rectangle: name and time, then the countdown.
struct RectangularPrayerWidgetView: View {
    let entry: PrayerWidgetEntry
    var countdown: WidgetCountdownMode = .live

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("NEXT")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text("\(entry.next.prayer.displayName) \(PrayerWidgetText.time(entry.next.time, timeZone: entry.timeZone))")
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            WidgetCountdownText(entry: entry, mode: countdown)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Lock screen rectangle, second style: the five times in a row, the current one marked.
/// Colors are left to the system so vibrant rendering works.
struct TodayTimesRectangularView: View {
    let entry: PrayerWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRAYER TIMES")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 2) {
                ForEach(entry.rows, id: \.prayer) { row in
                    column(for: row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func column(for row: PrayerWidgetRow) -> some View {
        let isCurrent = row.prayer == entry.current
        return VStack(spacing: 0) {
            Text(PrayerWidgetText.abbreviation(row.prayer))
                .font(.system(size: 10, weight: .bold))
            Text(PrayerWidgetText.compactTime(row.time, timeZone: entry.timeZone))
                .font(.system(size: 13, weight: .heavy))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(isCurrent ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.25))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? Text("Now") : Text(""))
    }
}

/// Lock screen inline line above the clock: "Asr at 3:15 PM".
struct InlinePrayerWidgetView: View {
    let entry: PrayerWidgetEntry

    var body: some View {
        Text(PrayerWidgetText.inline(entry))
    }
}
