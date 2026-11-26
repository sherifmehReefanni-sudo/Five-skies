import CoreLocation
import Foundation

/// Asks for when-in-use permission and publishes one device coordinate.
/// `coordinate` stays nil when permission is denied or the location is unavailable.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: Coordinate?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// True while a permission prompt or a location request is outstanding.
    @Published private(set) var isRequesting = false

    private let manager = CLLocationManager()
    private var isStarted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    /// Permission was refused or is not allowed on this device.
    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Whether a fix may still arrive: permission is granted, or it is not decided yet and
    /// a request is in flight (or the provider has not started, so the request is about to go out).
    var isAwaitingFix: Bool {
        guard coordinate == nil else { return false }
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        case .notDetermined:
            return isRequesting || !isStarted
        default:
            return false
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        handle(manager.authorizationStatus)
    }

    /// Asks for permission when it is not decided, or tries for a fresh fix when it is granted.
    /// When permission was refused the location pill opens iPhone Settings instead.
    func requestAgain() {
        guard !isDenied else { return }
        isStarted = true
        handle(manager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard isStarted else { return }
        handle(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        isRequesting = false
        coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Required by requestLocation(). A failed fix keeps whatever was published before,
        // and with nothing published the UI shows the labelled fallback.
        isRequesting = false
    }

    private func handle(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .notDetermined:
            isRequesting = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isRequesting = true
            manager.requestLocation()
        case .denied, .restricted:
            isRequesting = false
            coordinate = nil
        @unknown default:
            isRequesting = false
            coordinate = nil
        }
    }
}
