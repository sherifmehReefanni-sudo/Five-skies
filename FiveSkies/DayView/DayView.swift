import SwiftUI

/// The whole day at a glance: each prayer's window, sunrise, the extra times, and two day settings.
/// Presented as a sheet from Today. Reads AppSettings and the clock from the environment.
struct DayView: View {
    let service: PrayerTimesService
    let place: Place

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.appClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @Environment(\.motionEnabled) private var motionEnabled

    /// Days away from today; 0 is today in the place's time zone.
    @State private var dayOffset = 0
    @State private var cityName: String?
    @State private var revealed = false

    init(service: PrayerTimesService, place: Place) {
        self.service = service
        self.place = place
    }

    var body: some View {
        let configured = service.applying(method: settings.calculationMethod, asrRule: settings.asrRule)
        return TimelineView(.periodic(from: clock.now(), by: 60)) { _ in
            screen(now: clock.now(), configured: configured)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            revealed = true
        }
        .task(id: placeKey) {
            cityName = await PlaceNameProvider.shared.cityName(for: place)
        }
    }

    private var placeKey: String {
        place.isFallback ? "fallback" : PlaceNameProvider.cacheKey(for: place.coordinate)
    }

    private var cityText: String {
        if place.isFallback {
            return PlaceNameProvider.fallbackName
        }
        return cityName ?? "Your location"
    }

    private func screen(now: Date, configured: PrayerTimesService) -> some View {
        let shownDate = place.calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        let isToday = dayOffset == 0
        let schedule = configured.daySchedule(for: place, on: shownDate)
        let skyPhase = configured.prayerDay(for: place, on: now)?.skyPhase(at: now)
        let format = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.timeZone)
        return ZStack {
            skyBackground(skyPhase)
            VStack(spacing: 0) {
                header(date: shownDate, isToday: isToday)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let schedule = schedule {
                            prayersCard(schedule, now: now, isToday: isToday, format: format)
                                .riseIn(revealed: revealed, delay: 0.05)
                            extrasCard(schedule, format: format)
                                .riseIn(revealed: revealed, delay: 0.12)
                        } else {
                            unavailableCard
                        }
                        settingsCard
                            .riseIn(revealed: revealed, delay: 0.18)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private func skyBackground(_ skyPhase: Prayer?) -> some View {
        if let skyPhase = skyPhase {
            ZStack {
                SkyView(phase: skyPhase, showsCelestial: false)
                SkyLegibilityScrim(phase: skyPhase)
            }
        } else {
            Color.clear
                .moreSkyBackground(.calendar)
        }
    }

    // MARK: Header

    private func header(date: Date, isToday: Bool) -> some View {
        var titleStyle = Self.titleStyle
        titleStyle.timeZone = place.timeZone
        let hijri = DayHijriDate.text(for: date, adjustment: settings.hijriAdjustment, timeZone: place.timeZone)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(MorePalette.ink.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
                .accessibilityLabel("Close")
                .accessibilityIdentifier("dayClose")
                Spacer(minLength: 8)
                if !isToday {
                    Button {
                        move(to: 0)
                    } label: {
                        Text("Today")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(MorePalette.ink)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(MorePalette.goldGradient))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle(pressedScale: 0.94))
                    .accessibilityIdentifier("dayToday")
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 44)

            HStack(spacing: 8) {
                dayButton(symbol: "chevron.left", label: "Previous day", identifier: "dayPrevious") {
                    move(to: dayOffset - 1)
                }
                VStack(spacing: 3) {
                    Text(date.formatted(titleStyle))
                        .font(.title2.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.opacity)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("dayViewTitle")
                    Text(hijri)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MorePalette.goldLight)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.opacity)
                        .accessibilityLabel(Text("Hijri date, \(hijri)"))
                        .accessibilityIdentifier("dayHijriDate")
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.caption2.weight(.bold))
                            .accessibilityHidden(true)
                        Text(cityText)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(MorePalette.secondaryText)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Place, \(cityText)"))
                    .accessibilityIdentifier("dayCity")
                }
                .frame(maxWidth: .infinity)
                dayButton(symbol: "chevron.right", label: "Next day", identifier: "dayNext") {
                    move(to: dayOffset + 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .moreGlass(.dark, cornerRadius: 26)
        }
        .sensoryFeedback(.selection, trigger: dayOffset)
    }

    private func dayButton(
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
        .buttonStyle(PressScaleButtonStyle(pressedScale: 0.9))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private func move(to offset: Int) {
        withAnimation(motionEnabled ? .easeInOut(duration: 0.25) : nil) {
            dayOffset = offset
        }
    }

    // MARK: Cards

    private func prayersCard(_ schedule: DaySchedule, now: Date, isToday: Bool, format: Date.FormatStyle) -> some View {
        let rows = DayViewContent.prayerRows(for: schedule, ishaEnd: settings.ishaEnd)
        let current = isToday ? DayViewContent.currentRowID(in: rows, at: now) : nil
        return VStack(alignment: .leading, spacing: 6) {
            MoreCaption(text: "Prayer times")
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            ForEach(rows) { row in
                DayTimeRowView(
                    row: row,
                    format: format,
                    isCurrent: row.id == current,
                    isProminent: row.end != nil
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 26)
    }

    private func extrasCard(_ schedule: DaySchedule, format: Date.FormatStyle) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MoreCaption(text: "More times")
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 6)
            Text(DayDefinitions.commonPracticeNote)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MorePalette.goldLight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
                .accessibilityIdentifier("dayCommonPracticeNote")
            rowGroup(nil, rows: [DayViewContent.duhaRow(for: schedule)], format: format)
            rowGroup("Discouraged for voluntary prayer", rows: DayViewContent.discouragedRows(for: schedule), format: format)
            Text(DayDefinitions.discouragedNote)
                .font(.caption.weight(.medium))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .accessibilityIdentifier("dayDiscouragedNote")
            rowGroup("Night", rows: DayViewContent.nightRows(for: schedule), format: format)
            rowGroup("Fasting", rows: DayViewContent.fastingRows(for: schedule), format: format)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 26)
    }

    @ViewBuilder
    private func rowGroup(_ heading: String?, rows: [DayTimeRow], format: Date.FormatStyle) -> some View {
        if let heading = heading {
            Text(heading)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(MorePalette.secondaryText)
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        }
        ForEach(rows) { row in
            DayTimeRowView(row: row, format: format, isCurrent: false, isProminent: false)
        }
    }

    private var unavailableCard: some View {
        Text("Prayer times are not available for this day here.")
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            .frame(maxWidth: .infinity)
            .moreGlass(.dark, cornerRadius: 26)
            .accessibilityIdentifier("dayUnavailable")
    }

    private var settingsCard: some View {
        let adjustment = DayViewContent.hijriAdjustmentText(settings.hijriAdjustment)
        return VStack(alignment: .leading, spacing: 10) {
            MoreCaption(text: "Day settings")
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                Text("Isha ends at")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 8)
                Picker("Isha ends at", selection: $settings.ishaEnd) {
                    ForEach(IshaEndRule.allCases) { rule in
                        Text(rule.displayName).tag(rule)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color(hex: 0xFFE0A3))
                .accessibilityIdentifier("dayIshaEndPicker")
            }
            .frame(minHeight: 44)
            Text(DayDefinitions.ishaEndNote)
                .font(.caption.weight(.medium))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dayIshaEndNote")
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
                .accessibilityHidden(true)
            Stepper(value: $settings.hijriAdjustment, in: AppSettings.hijriAdjustmentRange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hijri date adjustment")
                        .font(.subheadline.weight(.bold))
                    Text(adjustment)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                }
            }
            .frame(minHeight: 44)
            .accessibilityValue(Text(adjustment))
            .accessibilityIdentifier("dayHijriStepper")
            Text("Moves the Hijri date by up to two days to match the moon sighting where you live.")
                .font(.caption.weight(.medium))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 26)
    }

    private static let titleStyle: Date.FormatStyle = {
        var style = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        style.calendar = Calendar(identifier: .gregorian)
        return style
    }()
}

/// One time or window, read by VoiceOver as one sentence. The current prayer is lit gold.
private struct DayTimeRowView: View {
    let row: DayTimeRow
    let format: Date.FormatStyle
    let isCurrent: Bool
    /// Prayer windows are bold; single moments and extra times are a step lighter.
    let isProminent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(row.title)
                .font(isProminent ? .headline.weight(.heavy) : .subheadline.weight(.bold))
            if isCurrent {
                Text("NOW")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.5)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(MorePalette.ink.opacity(0.14)))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.start.formatted(format))
                    .font(isProminent ? .headline.weight(.heavy) : .subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let end = row.end {
                    Text("until \(end.formatted(format))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .opacity(0.8)
                        .contentTransition(.numericText())
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(isCurrent ? MorePalette.ink : Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, isProminent ? 10 : 8)
        .frame(maxWidth: .infinity, minHeight: isProminent ? 54 : 46, alignment: .leading)
        .background(rowBackground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityAddTraits(isCurrent ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("dayRow-\(row.id)")
    }

    private var spoken: String {
        let text = row.spokenText(format)
        return isCurrent ? text + ", now" : text
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isCurrent {
            shape.fill(MorePalette.goldGradient)
                .shadow(color: MorePalette.gold.opacity(0.35), radius: 10, y: 4)
        } else {
            shape.fill(Color.white.opacity(0.06))
        }
    }
}
