import SwiftUI
import UIKit

/// Month or year prayer timetable for the user's place, with export as a PDF.
/// Pushed inside the More tab's NavigationStack, so it has none of its own.
struct TimetableView: View {
    // Like the Qibla tab, this screen owns its own LocationProvider.
    @StateObject private var location: LocationProvider
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.appClock) private var clock

    @State private var scope: TimetableScope = .month
    /// nil means the month or year containing today.
    @State private var selection: TimetableSelection?
    @State private var months: [TimetableMonth] = []
    @State private var builtKey: TimetableKey?
    @State private var locatingTimedOut = false
    @State private var isExporting = false
    @State private var export: TimetableExport?
    @State private var exportFailed = false

    /// How long to wait for the first fix before using the Makkah fallback, as on Today.
    private static let locatingTimeout: UInt64 = 4_000_000_000

    private let launch: LaunchOptions

    init() {
        launch = LaunchOptions()
        _location = StateObject(wrappedValue: LocationProvider())
    }

    var body: some View {
        let shownPlace = place
        let now = clock.now()
        let current = currentSelection(for: shownPlace, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MoreScreenTitle(text: "Timetable", identifier: "timetableTitle")
                placeCard(shownPlace)
                controls(current: current, place: shownPlace)
                exportButton(enabled: shownPlace != nil)
                tableSection(place: shownPlace, now: now)
                Text(TimetablePDF.footer)
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
        .task(id: tableKey) {
            rebuild(for: tableKey)
        }
        .sheet(item: $export) { item in
            TimetableShareSheet(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .alert("The PDF could not be made", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
        .sensoryFeedback(trigger: export?.id) { _, shown in
            shown == nil ? nil : .success
        }
    }

    // MARK: - Place

    private var requestsLocation: Bool {
        launch.requestsLocation
    }

    /// Where the times are for, or nil while the first device fix is still expected.
    private var place: Place? {
        if launch.fixedPhase != nil {
            return Place.makkahFallback
        }
        if let coordinate = location.coordinate {
            return Place.device(coordinate)
        }
        if requestsLocation && !locatingTimedOut && location.isAwaitingFix {
            return nil
        }
        return Place.makkahFallback
    }

    private func currentSelection(for place: Place?, now: Date) -> TimetableSelection {
        if let selection {
            return selection
        }
        let parts = (place ?? Place.makkahFallback).calendar.dateComponents([.year, .month], from: now)
        return TimetableSelection(year: parts.year ?? 2026, month: parts.month ?? 1)
    }

    private var tableKey: TimetableKey? {
        guard let place else { return nil }
        return TimetableKey(
            scope: scope,
            selection: currentSelection(for: place, now: clock.now()),
            place: place,
            method: settings.calculationMethod,
            asrRule: settings.asrRule,
            hijriAdjustment: settings.hijriAdjustment
        )
    }

    private func builder(for key: TimetableKey) -> TimetableBuilder {
        TimetableBuilder(
            place: key.place,
            service: PrayerTimesService().applying(method: key.method, asrRule: key.asrRule),
            hijriAdjustment: key.hijriAdjustment
        )
    }

    private func rebuild(for key: TimetableKey?) {
        guard let key else {
            months = []
            builtKey = nil
            return
        }
        months = builder(for: key).months(for: key.selection, scope: key.scope)
        builtKey = key
    }

    // MARK: - Header cards

    private func placeCard(_ place: Place?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MoreCaption(text: "Times for")
            Text(place.map { TimetableBuilder.placeLabel(for: $0) } ?? "Finding your location")
                .font(.headline.weight(.heavy))
                .accessibilityIdentifier("timetablePlace")
            Text("\(settings.calculationMethod.displayName). Asr: \(settings.asrRule.displayName).")
                .font(.footnote.weight(.medium))
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .moreGlass(.light, cornerRadius: 22)
    }

    private func controls(current: TimetableSelection, place: Place?) -> some View {
        let calendar = (place ?? Place.makkahFallback).calendar
        let title = scope == .month
            ? TimetableBuilder.monthTitle(for: current, calendar: calendar, locale: .current)
            : String(current.year)
        let unit = scope == .month ? "month" : "year"
        return VStack(spacing: 12) {
            Picker("Range", selection: $scope) {
                ForEach(TimetableScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)
            .accessibilityIdentifier("timetableScope")

            HStack(spacing: 8) {
                stepButton(symbol: "chevron.left", label: "Previous \(unit)", identifier: "timetablePrevious") {
                    selection = current.stepped(by: -1, scope: scope)
                }
                Text(title)
                    .font(.title3.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("timetablePeriodTitle")
                stepButton(symbol: "chevron.right", label: "Next \(unit)", identifier: "timetableNext") {
                    selection = current.stepped(by: 1, scope: scope)
                }
            }
        }
        .padding(14)
        .moreGlass(.dark, cornerRadius: 24)
    }

    private func stepButton(
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

    // MARK: - Export

    private func exportButton(enabled: Bool) -> some View {
        Button(action: exportPDF) {
            HStack(spacing: 8) {
                if isExporting {
                    ProgressView()
                        .tint(MorePalette.ink)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.bold))
                }
                Text("Export PDF")
                    .font(.headline.weight(.heavy))
            }
            .foregroundStyle(MorePalette.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(MorePalette.goldGradient))
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled || isExporting)
        .accessibilityIdentifier("timetableExport")
    }

    private func exportPDF() {
        guard let key = tableKey, !isExporting else { return }
        isExporting = true
        let pages = builtKey == key ? months : builder(for: key).months(for: key.selection, scope: key.scope)
        let info = TimetableDocumentInfo(
            placeLabel: TimetableBuilder.placeLabel(for: key.place),
            methodName: key.method.displayName,
            asrRuleName: key.asrRule.displayName,
            timeZone: key.place.timeZone,
            locale: .current
        )
        let fileName = TimetablePDF.fileName(for: key.selection, scope: key.scope)
        Task { @MainActor in
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                try? TimetablePDF.writeFile(months: pages, info: info, fileName: fileName)
            }.value
            isExporting = false
            if let url {
                export = TimetableExport(url: url)
            } else {
                exportFailed = true
            }
        }
    }

    // MARK: - Table

    @ViewBuilder
    private func tableSection(place: Place?, now: Date) -> some View {
        if let place, builtKey != nil, builtKey == tableKey, !months.isEmpty {
            let format = TimetableTimeFormat(timeZone: place.timeZone, includesPeriod: false)
            let calendar = place.calendar
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(months) { month in
                    monthHeading(month)
                        .padding(.top, month.id == months.first?.id ? 0 : 14)
                    TimetableColumnHeader()
                    ForEach(Array(month.rows.enumerated()), id: \.element.id) { index, row in
                        TimetableRowView(
                            row: row,
                            isStriped: index % 2 == 1,
                            isToday: calendar.isDate(row.date, inSameDayAs: now),
                            format: format
                        )
                    }
                }
            }
            .padding(10)
            .moreGlass(.dark, cornerRadius: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timetableTable")
        } else {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(place == nil ? "Finding your location" : "Working out the times")
                    .font(.headline.weight(.heavy))
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .moreGlass(.dark, cornerRadius: 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timetableLoading")
        }
    }

    private func monthHeading(_ month: TimetableMonth) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(month.title)
                .font(.headline.weight(.heavy))
            Spacer(minLength: 8)
            Text(month.hijriTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MorePalette.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Everything the on-screen table depends on, so it is rebuilt only when one of these changes.
private struct TimetableKey: Equatable {
    let scope: TimetableScope
    let selection: TimetableSelection
    let place: Place
    let method: PrayerCalculationMethod
    let asrRule: AsrRule
    let hijriAdjustment: Int
}

/// A finished PDF waiting in the share sheet.
private struct TimetableExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// Fixed widths for the two narrow columns; the six times share the rest.
private enum TimetableColumns {
    static let date: CGFloat = 40
    static let hijri: CGFloat = 34
    static let spacing: CGFloat = 2
}

private struct TimetableColumnHeader: View {
    var body: some View {
        let titles = TimetableBuilder.columnTitles
        HStack(spacing: TimetableColumns.spacing) {
            Text(titles[0])
                .frame(width: TimetableColumns.date)
            Text(titles[1])
                .frame(width: TimetableColumns.hijri)
            ForEach(titles.dropFirst(2), id: \.self) { title in
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption2.weight(.heavy))
        .foregroundStyle(MorePalette.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

private struct TimetableRowView: View {
    let row: TimetableRow
    let isStriped: Bool
    let isToday: Bool
    let format: TimetableTimeFormat

    var body: some View {
        HStack(spacing: TimetableColumns.spacing) {
            VStack(spacing: 0) {
                Text(String(row.gregorianDay))
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                Text(row.weekdayName)
                    .font(.caption2.weight(.semibold))
                    .opacity(0.8)
            }
            .frame(width: TimetableColumns.date)
            Text(String(row.hijriDay))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .opacity(0.8)
                .frame(width: TimetableColumns.hijri)
            ForEach(Array(row.times.enumerated()), id: \.offset) { item in
                Text(format.string(item.element))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundStyle(isToday ? MorePalette.gold : Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isStriped ? 0.07 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MorePalette.gold.opacity(isToday ? 0.6 : 0), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let names = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let times = zip(names, row.times).map { "\($0.0) \(format.string($0.1))" }.joined(separator: ", ")
        let base = "\(row.weekdayName) \(row.gregorianDay), Hijri day \(row.hijriDay), \(times)"
        return isToday ? "Today, " + base : base
    }
}

/// The system share sheet for the exported file.
private struct TimetableShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
