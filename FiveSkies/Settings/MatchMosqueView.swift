import SwiftUI

/// One calculation method with today's Fajr and Isha, for "Match your mosque" (plan N5).
struct MosqueMatchRow: Equatable, Identifiable {
    let method: PrayerCalculationMethod
    let fajr: Date
    let isha: Date
    /// The method the app uses now.
    let isCurrent: Bool

    var id: String { method.rawValue }

    /// One row per calculation method, in the order settings lists them, worked out the same
    /// way Today works out its times: `service` with each method and the user's Asr rule,
    /// for the day containing `date` in the place's own time zone.
    static func rows(
        service: PrayerTimesService,
        place: Place,
        on date: Date,
        current: PrayerCalculationMethod,
        asrRule: AsrRule
    ) -> [MosqueMatchRow] {
        PrayerCalculationMethod.allCases.compactMap { method in
            let configured = service.applying(method: method, asrRule: asrRule)
            guard let day = configured.prayerDay(for: place, on: date) else { return nil }
            return MosqueMatchRow(method: method, fajr: day.fajr, isha: day.isha, isCurrent: method == current)
        }
    }
}

/// Lists every calculation method with today's Fajr and Isha so the user can pick the one
/// that matches their mosque's timetable. Tapping a row selects that method.
/// Pushed from the calculation method row in SettingsView.
struct MatchMosqueView: View {
    let place: Place
    let service: PrayerTimesService

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.appClock) private var clock

    /// Counts selections, for the haptic.
    @State private var selections = 0

    init(place: Place, service: PrayerTimesService = PrayerTimesService()) {
        self.place = place
        self.service = service
    }

    var body: some View {
        let rows = MosqueMatchRow.rows(
            service: service,
            place: place,
            on: clock.now(),
            current: settings.calculationMethod,
            asrRule: settings.asrRule
        )
        let format = TileTimeFormat(timeZone: place.timeZone)
        return ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x050B24), location: 0),
                    .init(color: Color(hex: 0x141E55), location: 0.45),
                    .init(color: Color(hex: 0x3A2A6A), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MoreScreenTitle(text: "Match your mosque", identifier: "matchMosque")

                    Text("Methods differ mostly in when Fajr and Isha begin. Find the row whose times match your mosque's timetable, then tap it.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(placeLine)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            rowButton(row, format: format)
                        }
                    }
                    .padding(.top, 4)

                    Text("If you are not sure, keep this and ask your mosque.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .foregroundStyle(.white)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selections)
    }

    private var placeLine: String {
        place.isFallback
            ? "Today's times in Makkah, because your location is not known yet."
            : "Today's times where you are."
    }

    private func rowButton(_ row: MosqueMatchRow, format: TileTimeFormat) -> some View {
        let fajr = Self.clockText(row.fajr, format: format)
        let isha = Self.clockText(row.isha, format: format)
        return Button {
            guard settings.calculationMethod != row.method else { return }
            settings.calculationMethod = row.method
            selections += 1
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.method.displayName)
                        .font(.subheadline.weight(.heavy))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 14) {
                        Text("Fajr \(fajr)")
                        Text("Isha \(isha)")
                    }
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(MorePalette.secondaryText)
                }
                Spacer(minLength: 8)
                if row.isCurrent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                        Text("In use")
                    }
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(MorePalette.gold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .moreGlass(.light, cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MorePalette.gold.opacity(row.isCurrent ? 0.9 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(Text("\(row.method.displayName). Fajr \(fajr). Isha \(isha)."))
        .accessibilityValue(Text(row.isCurrent ? "In use" : ""))
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
        .accessibilityIdentifier("matchMosqueRow-\(row.method.rawValue)")
    }

    /// "5:12 AM" in 12-hour locales, "05:12" otherwise.
    private static func clockText(_ date: Date, format: TileTimeFormat) -> String {
        if let period = format.period(date) {
            return "\(format.time(date)) \(period)"
        }
        return format.time(date)
    }
}
