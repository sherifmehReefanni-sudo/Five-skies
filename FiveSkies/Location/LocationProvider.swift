import CoreLocation
import Foundation

/// Asks for when-in-use permission and publishes one device coordinate.
/// `coordinate` stays nil when permission is denied or the location is unavailable.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: Coordinate?

    private let manager = CLLocationManager()
    private var isStarted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        handle(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isStarted else { return }
        handle(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Required by requestLocation(). A failed fix keeps whatever was published before,
        // and with nothing published the UI shows the labelled fallback.
    }

    private func handle(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            coordinate = nil
        @unknown default:
            coordinate = nil
        }
    }
}
