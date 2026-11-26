import SwiftUI

/// Prayer tracker: current and best streak, and this week's grid of prayed dots.
struct TrackerView: View {
    @Environment(\.appClock) private var clock

    @State private var week: [TrackerDay] = []
    @State private var currentStreak = 0
    @State private var bestStreak = 0

    private let store = PrayedStore()
    private let streaks = StreakCalculator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Your prayers", identifier: "trackerTitle")
                streakCard
                weekCard
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.tracker)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            MoreCaption(text: "Current streak")
            Text(Self.daysText(currentStreak))
                .font(.system(size: 64, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("currentStreak")
            Text("Best: \(Self.daysText(bestStreak))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MorePalette.secondaryText)
                .accessibilityIdentifier("bestStreak")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week")
                    .font(.headline.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                legend
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(week) { day in
                    VStack(spacing: 0) {
                        Text(day.shortName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(day.isToday ? MorePalette.gold : MorePalette.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.bottom, 6)
                            .accessibilityHidden(true)
                        ForEach(Prayer.allCases) { prayer in
                            dot(day: day, prayer: prayer)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .moreGlass(.dark, cornerRadius: 28)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle().fill(MorePalette.mint).frame(width: 10, height: 10)
                Text("Prayed")
            }
            HStack(spacing: 5) {
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 2).frame(width: 10, height: 10)
                Text("Missed")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(MorePalette.secondaryText)
        .accessibilityHidden(true)
    }

    private func dot(day: TrackerDay, prayer: Prayer) -> some View {
        let prayed = day.prayed.contains(prayer)
        return Button {
            toggle(prayer, on: day)
        } label: {
            ZStack {
                Circle()
                    .fill(prayed ? MorePalette.mint : Color.clear)
                Circle()
                    .strokeBorder(prayed ? MorePalette.mint : Color.white.opacity(0.6), lineWidth: 2)
            }
            .frame(width: 18, height: 18)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day.isFuture)
        .opacity(day.isFuture ? 0.35 : 1)
        .accessibilityLabel(Text("\(day.fullName), \(prayer.displayName), \(prayed ? "prayed" : "not prayed")"))
        .accessibilityAddTraits(prayed ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("dot-\(day.key)-\(prayer.rawValue)")
    }

    private func toggle(_ prayer: Prayer, on day: TrackerDay) {
        guard !day.isFuture else { return }
        store.setPrayed(!day.prayed.contains(prayer), prayer, on: day.date)
        reload()
    }

    private func reload() {
        let now = clock.now()
        week = TrackerDay.week(containing: now, store: store, calendar: streaks.calendar)
        let complete = PrayedStore.completeDayKeys()
        currentStreak = streaks.currentStreak(completedDays: complete, today: now)
        bestStreak = streaks.bestStreak(completedDays: complete)
    }

    private static func daysText(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

/// One column of the "This week" grid.
struct TrackerDay: Identifiable {
    let date: Date
    let key: String
    let shortName: String
    let fullName: String
    let prayed: Set<Prayer>
    let isToday: Bool
    let isFuture: Bool

    var id: String { key }

    /// The seven days of the calendar week containing `now`, first weekday from the user's locale.
    static func week(containing now: Date, store: PrayedStore, calendar base: Calendar) -> [TrackerDay] {
        var calendar = base
        calendar.locale = Locale.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today

        let shortFormatter = DateFormatter()
        shortFormatter.calendar = calendar
        shortFormatter.timeZone = calendar.timeZone
        shortFormatter.locale = Locale.current
        shortFormatter.dateFormat = "EEE"

        let fullFormatter = DateFormatter()
        fullFormatter.calendar = calendar
        fullFormatter.timeZone = calendar.timeZone
        fullFormatter.locale = Locale.current
        fullFormatter.dateFormat = "EEEE"

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return TrackerDay(
                date: date,
                key: store.dayKey(for: date),
                shortName: shortFormatter.string(from: date),
                fullName: fullFormatter.string(from: date),
                prayed: store.prayers(on: date),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isFuture: date > today
            )
        }
    }
}
