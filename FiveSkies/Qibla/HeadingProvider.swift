import CoreLocation
import Foundation

/// Publishes the device compass heading in degrees from north.
/// `heading` stays nil when the device has no compass, such as the simulator.
final class HeadingProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var heading: Double?

    private let fixedHeading: Double?
    private let manager = CLLocationManager()
    private var isUpdating = false

    /// With a `fixedHeading`, that value is reported and CoreLocation heading updates never start.
    init(fixedHeading: Double? = nil) {
        self.fixedHeading = fixedHeading
        _heading = Published(initialValue: fixedHeading)
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
    }

    func start() {
        if let fixedHeading = fixedHeading {
            heading = fixedHeading
            return
        }
        guard !isUpdating, CLLocationManager.headingAvailable() else { return }
        isUpdating = true
        manager.startUpdatingHeading()
    }

    func stop() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // trueHeading is negative when it cannot be determined, for example without location access.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard value >= 0 else { return }
        heading = value
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed reading keeps the last heading; with none, the UI shows the no compass guidance.
    }
}
