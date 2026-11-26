import SwiftUI

/// Hijri calendar: a Gregorian month grid with the Umm al-Qura Hijri day under each date.
struct HijriCalendarView: View {
    @Environment(\.appClock) private var clock
    @State private var monthOffset = 0

    private let math = HijriCalendarMath()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        let now = clock.now()
        let monthStart = math.monthStart(containing: now, offset: monthOffset)
        let showsCurrentMonth = monthOffset == 0
        let titleDate = showsCurrentMonth ? now : middleOfMonth(monthStart)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MoreScreenTitle(text: "Hijri calendar", identifier: "hijriTitle")
                VStack(spacing: 10) {
                    header(titleDate: titleDate, monthStart: monthStart)
                    weekdayRow
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(math.slots(forMonthStarting: monthStart)) { slot in
                            if let cell = slot.cell {
                                dayCell(cell, isToday: math.gregorian.isDate(cell.date, inSameDayAs: now))
                            } else {
                                Color.clear
                                    .frame(minHeight: 48)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .moreGlass(.dark, cornerRadius: 26)

                Text("Hijri dates use the Umm al-Qura calculation and can differ by a day from local moon sighting.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MorePalette.secondaryText)
                    .padding(.horizontal, 8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .moreSkyBackground(.calendar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(titleDate: Date, monthStart: Date) -> some View {
        HStack(spacing: 8) {
            monthButton(symbol: "chevron.left", label: "Previous month", identifier: "hijriPrevious") {
                monthOffset -= 1
            }
            VStack(spacing: 2) {
                Text(math.hijriMonthTitle(for: titleDate))
                    .font(.title2.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("hijriMonthTitle")
                Text(math.gregorianMonthTitle(for: monthStart))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityIdentifier("gregorianMonthTitle")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            monthButton(symbol: "chevron.right", label: "Next month", identifier: "hijriNext") {
                monthOffset += 1
            }
        }
    }

    private func monthButton(
        symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.1)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private var weekdayRow: some View {
        let symbols = math.weekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MorePalette.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func dayCell(_ cell: HijriDayCell, isToday: Bool) -> some View {
        VStack(spacing: 0) {
            Text("\(cell.gregorianDay)")
                .font(.subheadline.weight(isToday ? .black : .semibold))
            Text("\(cell.hijriDay)")
                .font(.caption2.weight(.semibold))
                .opacity(0.75)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(isToday ? MorePalette.ink : Color.white)
        .frame(width: 40, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isToday ? AnyShapeStyle(MorePalette.goldGradient) : AnyShapeStyle(Color.clear))
        )
        .shadow(color: isToday ? MorePalette.gold.opacity(0.4) : .clear, radius: 10, y: 6)
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dayLabel(cell, isToday: isToday)))
    }

    private func dayLabel(_ cell: HijriDayCell, isToday: Bool) -> String {
        let base = "\(math.gregorianDayTitle(for: cell.date)), Hijri day \(cell.hijriDay)"
        return isToday ? base + ", today" : base
    }

    private func middleOfMonth(_ monthStart: Date) -> Date {
        math.gregorian.date(byAdding: .day, value: 14, to: monthStart) ?? monthStart
    }
}
