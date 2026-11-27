import MapKit
import SwiftUI
import UIKit

/// Mosques nearby, from Apple Maps.
struct MosquesView: View {
    init() {}

    var body: some View {
        PlacesScreen(kind: .mosques)
    }
}

/// Halal food nearby, from Apple Maps.
struct HalalFoodView: View {
    init() {}

    var body: some View {
        PlacesScreen(kind: .halal)
    }
}

/// The words, symbol and sky for each places screen.
extension PlaceKind {
    var title: String {
        switch self {
        case .mosques: return "Mosques nearby"
        case .halal: return "Halal food"
        }
    }

    var titleIdentifier: String {
        switch self {
        case .mosques: return "mosquesTitle"
        case .halal: return "halalTitle"
        }
    }

    var symbol: String {
        switch self {
        case .mosques: return "building.columns"
        case .halal: return "fork.knife"
        }
    }

    var note: String {
        switch self {
        case .mosques:
            return "Results come from Apple Maps. Prayer and iqamah times are not shown yet."
        case .halal:
            return "Results come from Apple Maps and are not verified. Always confirm halal status with the restaurant."
        }
    }

    var emptyText: String {
        "Nothing found nearby"
    }

    var sky: LinearGradient {
        let colors: [Color]
        switch self {
        case .mosques:
            colors = [Color(hex: 0x071433), Color(hex: 0x1F4C7A), Color(hex: 0x3A3F8F), Color(hex: 0x2A1638)]
        case .halal:
            colors = [Color(hex: 0x0B1030), Color(hex: 0x3A2F7A), Color(hex: 0x7A3F6B), Color(hex: 0x2A1638)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var panelGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .mosques:
            colors = [Color(hex: 0x1F4C7A), Color(hex: 0x40C8B4, opacity: 0.6), Color(hex: 0x3A3F8F)]
        case .halal:
            colors = [Color(hex: 0x6B3F8F), Color(hex: 0xF09650, opacity: 0.6), Color(hex: 0x3A2F7A)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A small single-colour mosque: a central dome with a thin finial and two slim minarets.
struct MosqueGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x0 * w, y: rect.minY + y0 * h, width: (x1 - x0) * w, height: (y1 - y0) * h)
        }

        var path = Path()

        // Dome.
        path.move(to: point(0.30, 0.62))
        path.addQuadCurve(to: point(0.70, 0.62), control: point(0.50, 0.02))
        path.closeSubpath()

        // Thin finial above the dome.
        path.addRect(box(0.485, 0.14, 0.515, 0.33))
        path.addEllipse(in: box(0.46, 0.09, 0.54, 0.17))

        // Prayer hall under the dome.
        path.addRect(box(0.26, 0.62, 0.74, 0.88))

        // Two slim minarets, each with a pointed cap.
        for (left, right) in [(CGFloat(0.09), CGFloat(0.19)), (CGFloat(0.81), CGFloat(0.91))] {
            path.addRect(box(left, 0.40, right, 0.88))
            path.move(to: point(left - 0.01, 0.40))
            path.addLine(to: point((left + right) / 2, 0.20))
            path.addLine(to: point(right + 0.01, 0.40))
            path.closeSubpath()
        }

        // Ground line.
        path.addRect(box(0.05, 0.88, 0.95, 0.93))

        return path
    }
}

/// The shared places screen: a map panel, then a glass list of results, then the source note.
struct PlacesScreen: View {
    let kind: PlaceKind

    // Like the Qibla tab, this screen owns its own LocationProvider.
    @StateObject private var location: LocationProvider
    @StateObject private var model: PlacesSearchModel

    @State private var camera: MapCameraPosition = .automatic
    @State private var revealed = false

    @Environment(\.openURL) private var openURL

    /// The fixed screenshot mode: sample rows, no location and no MapKit.
    private let usesSamples: Bool
    private let requestsLocation: Bool

    init(kind: PlaceKind) {
        let launch = LaunchOptions()
        let usesSamples = launch.fixedPhase != nil
        self.kind = kind
        self.usesSamples = usesSamples
        self.requestsLocation = launch.requestsLocation
        _location = StateObject(wrappedValue: LocationProvider())
        let searcher: PlaceSearching = usesSamples ? FakePlaceSearch.samples(for: kind) : MapKitPlaceSearch()
        _model = StateObject(wrappedValue: PlacesSearchModel(searcher: searcher, query: kind.query))
    }

    private var state: PlacesScreenState {
        PlacesScreenState.resolve(
            usesSamples: usesSamples,
            isDenied: location.isDenied,
            isAwaitingFix: location.isAwaitingFix,
            hasCoordinate: location.coordinate != nil,
            outcome: model.outcome
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MoreScreenTitle(text: kind.title, identifier: kind.titleIdentifier)
                mapPanel
                    .riseIn(revealed: revealed, delay: 0.05)
                content
                    .riseIn(revealed: revealed, delay: 0.12)
                Text(kind.note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MorePalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("placesNote")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(kind.sky.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: begin)
        .onChange(of: location.coordinate) { _, coordinate in
            guard !usesSamples, let coordinate else { return }
            centre(on: coordinate)
            model.search(near: coordinate)
        }
        .onChange(of: model.outcome) { _, outcome in
            if case .found(let places) = outcome, !places.isEmpty, !usesSamples {
                camera = .automatic
            }
        }
    }

    private func begin() {
        revealed = true
        if usesSamples {
            model.search(near: FakePlaceSearch.sampleOrigin)
            return
        }
        guard requestsLocation else { return }
        location.start()
        if let coordinate = location.coordinate {
            centre(on: coordinate)
            model.search(near: coordinate)
        }
    }

    private func centre(on coordinate: Coordinate) {
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            latitudinalMeters: 6_000,
            longitudinalMeters: 6_000
        ))
    }

    // MARK: - Map

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    private var mapPanel: some View {
        Group {
            if !usesSamples, location.coordinate != nil {
                Map(position: $camera) {
                    UserAnnotation()
                    ForEach(mapPlaces) { place in
                        Marker(
                            place.name,
                            systemImage: kind.symbol,
                            coordinate: CLLocationCoordinate2D(
                                latitude: place.coordinate.latitude,
                                longitude: place.coordinate.longitude
                            )
                        )
                    }
                }
                .accessibilityLabel(Text("Map of \(kind.title.lowercased())"))
            } else {
                // A plain panel stands in for the map in the screenshot mode and before a location is known.
                ZStack {
                    kind.panelGradient
                    placeholderGlyph
                }
                .accessibilityElement()
                .accessibilityLabel(Text("Map"))
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipShape(panelShape)
        .overlay(panelShape.strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
        .accessibilityIdentifier("placesMap")
    }

    /// The placeholder glyph: a drawn mosque for mosques, the fork and knife symbol for halal food.
    @ViewBuilder
    private var placeholderGlyph: some View {
        switch kind {
        case .mosques:
            MosqueGlyph()
                .fill(Color.white.opacity(0.85))
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
        case .halal:
            Image(systemName: kind.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var mapPlaces: [PlaceResult] {
        if case .results(let places) = state {
            return places
        }
        return []
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        switch state {
        case .locating:
            statusCard(text: "Finding your location", showsProgress: true, identifier: "placesLocating")
        case .searching:
            statusCard(text: "Searching nearby", showsProgress: true, identifier: "placesSearching")
        case .results(let places):
            resultsList(places)
        case .empty:
            statusCard(text: kind.emptyText, showsProgress: false, identifier: "placesEmpty")
        case .needsPermission:
            permissionCard
        case .locationFailed:
            failureCard(
                text: "Your location could not be found.",
                retry: { location.requestAgain() }
            )
        case .searchFailed:
            failureCard(
                text: "The search did not finish. Check your connection and try again.",
                retry: { model.retry() }
            )
        }
    }

    private func statusCard(text: String, showsProgress: Bool, identifier: String) -> some View {
        HStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .tint(.white)
            }
            Text(text)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location is off")
                .font(.headline.weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            Text("Allow location for Five Skies in iPhone Settings to search near you. Your location stays on this device and Apple Maps.")
                .font(.subheadline)
                .foregroundStyle(MorePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            actionButton(title: location.isDenied ? "Open Settings" : "Use my location") {
                // The same action as the location pill.
                if location.isDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } else {
                    location.requestAgain()
                }
            }
            .accessibilityIdentifier("placesPermission")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
    }

    private func failureCard(text: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            actionButton(title: "Retry", action: retry)
                .accessibilityIdentifier("placesRetry")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .moreGlass(.dark, cornerRadius: 24)
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.heavy))
                .foregroundStyle(MorePalette.ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Capsule().fill(MorePalette.goldGradient))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Results

    private func resultsList(_ places: [PlaceResult]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                if index > 0 {
                    Divider()
                        .overlay(Color.white.opacity(0.2))
                        .padding(.leading, 16)
                }
                row(place, index: index)
            }
        }
        .moreGlass(.dark, cornerRadius: 24)
    }

    private func row(_ place: PlaceResult, index: Int) -> some View {
        let distance = PlaceFormatting.distanceText(place.distance)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: place.name)
                    .font(.headline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: distance)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MorePalette.gold)
                if let address = place.address {
                    Text(verbatim: address)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MorePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("placeRow-\(index)")

            Button {
                // Sample rows are not real places, so they open nothing.
                guard !usesSamples else { return }
                PlaceFormatting.openDirections(to: place)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MorePalette.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MorePalette.goldGradient))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(Text("Directions to \(place.name)"))
            .accessibilityHint(Text("Opens Apple Maps"))
            .accessibilityIdentifier("placeDirections-\(index)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
