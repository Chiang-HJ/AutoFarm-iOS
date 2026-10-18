import CoreLocation
import Foundation

public final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    public static let shared = BackgroundKeepAlive()

    private let manager = CLLocationManager()
    public private(set) var lastKnownCoordinate: CLLocationCoordinate2D?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
    }

    public func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownCoordinate = locations.last?.coordinate
    }
}
