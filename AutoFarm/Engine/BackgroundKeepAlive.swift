import CoreLocation
import Foundation

public final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    public static let shared = BackgroundKeepAlive()

    private let manager = CLLocationManager()
    public private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    private var isRunning = false

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    public func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownCoordinate = locations.last?.coordinate
        // 系統在背景給予位置事件時，立即觸發心跳維持 DVT 虛擬座標錨定
        AutoFarmSession.shared.backgroundTickKeepAlive()
    }
}
