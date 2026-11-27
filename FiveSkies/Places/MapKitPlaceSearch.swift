import Foundation
import MapKit

/// Searches Apple Maps with `MKLocalSearch`. Needs no API key.
struct MapKitPlaceSearch: PlaceSearching {
    func search(query: String, near origin: Coordinate, radius: Double) async throws -> [PlaceResult] {
        let center = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.resultTypes = .pointOfInterest

        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            // MapKit reports "nothing found" as an error.
            return []
        }

        let results = response.mapItems.compactMap { item -> PlaceResult? in
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let place = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let name = item.name ?? ""
            guard !name.isEmpty else { return nil }
            let address = item.placemark.title.flatMap { $0.isEmpty ? nil : $0 }
            return PlaceResult(
                name: name,
                coordinate: place,
                distance: PlaceDistance.metres(from: origin, to: place),
                address: address,
                phone: item.phoneNumber,
                url: item.url
            )
        }
        return PlaceDistance.sorted(results)
    }
}

/// Formatting and Apple Maps hand off for a result.
enum PlaceFormatting {
    private static let formatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// The distance in the units of the user's locale, such as "1.2 km" or "0.7 mi".
    static func distanceText(_ metres: Double) -> String {
        formatter.string(fromDistance: metres)
    }

    /// Opens Apple Maps with driving directions to the place.
    static func openDirections(to place: PlaceResult) {
        let coordinate = CLLocationCoordinate2D(
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude
        )
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.name
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}
