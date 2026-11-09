import SwiftUI
import MapKit
import UIKit

public struct MainMapView: UIViewRepresentable {
    @ObservedObject var session = AutoFarmSession.shared
    @ObservedObject var station = FlowerStationManager.shared
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onSelectWaypoint: ((Int) -> Void)?
    var onTapCurrentLocation: (() -> Void)?
    var onSelectStationPoint: ((FlowerStationPoint) -> Void)?

    public init(
        onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
        onSelectWaypoint: ((Int) -> Void)? = nil,
        onTapCurrentLocation: (() -> Void)? = nil,
        onSelectStationPoint: ((FlowerStationPoint) -> Void)? = nil
    ) {
        self.onLongPress = onLongPress
        self.onSelectWaypoint = onSelectWaypoint
        self.onTapCurrentLocation = onTapCurrentLocation
        self.onSelectStationPoint = onSelectStationPoint
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.showsScale = true

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        let initialCenter = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
        let region = MKCoordinateRegion(center: initialCenter, latitudinalMeters: 500, longitudinalMeters: 500)
        mapView.setRegion(region, animated: false)

        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // 1. 相機平滑滑回目前定位
        if session.cameraCenterTrigger != context.coordinator.lastCameraCenterTrigger {
            context.coordinator.lastCameraCenterTrigger = session.cameraCenterTrigger
            let target = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
            mapView.setCenter(target, animated: true)
        }

        // 2. 相機路線全覽
        if session.cameraRouteBoundsTrigger != context.coordinator.lastCameraRouteBoundsTrigger {
            context.coordinator.lastCameraRouteBoundsTrigger = session.cameraRouteBoundsTrigger
            let pointsToFit = !session.originalBasePoints.isEmpty ? session.originalBasePoints : session.routePoints
            if !pointsToFit.isEmpty {
                var zoomRect = MKMapRect.null
                for node in pointsToFit {
                    let point = MKMapPoint(CLLocationCoordinate2D(latitude: node.lat, longitude: node.lng))
                    let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                    zoomRect = zoomRect.union(pointRect)
                }
                let insets = UIEdgeInsets(top: 90, left: 50, bottom: 260, right: 50)
                mapView.setVisibleMapRect(zoomRect, edgePadding: insets, animated: true)
            }
        }

        // 3. 更新目前位置標記 (角色圖示)
        let currentCoord = CLLocationCoordinate2D(latitude: session.currentLat, longitude: session.currentLng)
        if let currentAnno = context.coordinator.currentLocationAnnotation {
            UIView.animate(withDuration: 0.1) {
                currentAnno.coordinate = currentCoord
            }
        } else {
            let anno = MKPointAnnotation()
            anno.coordinate = currentCoord
            anno.title = "目前位置"
            mapView.addAnnotation(anno)
            context.coordinator.currentLocationAnnotation = anno
        }

        // 4. 更新航點數字球標記 (完全對齊安卓：只標記基準點/花苞，絕不標記數千個微小步進點)
        let waypoints = session.displayWaypoints
        let displayCount = waypoints.count
        let currentDisplayIdx = session.currentDisplayIndex

        if context.coordinator.cachedRouteCount != displayCount ||
           context.coordinator.cachedRouteName != session.activeRouteName ||
           context.coordinator.cachedCurrentIndex != currentDisplayIdx {
            
            context.coordinator.cachedRouteCount = displayCount
            context.coordinator.cachedRouteName = session.activeRouteName
            context.coordinator.cachedCurrentIndex = currentDisplayIdx

            // 移除舊航點標記
            let oldWaypoints = mapView.annotations.filter { $0 is WaypointAnnotation }
            mapView.removeAnnotations(oldWaypoints)

            if displayCount > 0 {
                var newAnnotations: [WaypointAnnotation] = []
                for i in 0..<displayCount {
                    let node = waypoints[i]
                    let isTarget = (i == currentDisplayIdx)
                    let isStart = (i == 0)
                    let anno = WaypointAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: node.lat, longitude: node.lng),
                        index: i,
                        isTarget: isTarget,
                        isStart: isStart,
                        label: node.label,
                        isFlower: (session.executionMode == 1)
                    )
                    newAnnotations.append(anno)
                }
                mapView.addAnnotations(newAnnotations)
            }
        }

        // 5. 更新連線軌跡折線：一律使用基準點/花點連心直線，絕不繪製數百個微步螺旋毛球線！
        let routeName = session.activeRouteName
        let baseCount = waypoints.count

        if context.coordinator.cachedOverlayRouteName != routeName ||
           context.coordinator.cachedOverlayPointsCount != baseCount {
            
            context.coordinator.cachedOverlayRouteName = routeName
            context.coordinator.cachedOverlayPointsCount = baseCount

            if let oldPolyline = context.coordinator.currentPolyline {
                mapView.removeOverlay(oldPolyline)
                context.coordinator.currentPolyline = nil
            }

            if baseCount > 1 {
                let coords = waypoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                mapView.addOverlay(polyline)
                context.coordinator.currentPolyline = polyline
            }
        }

        // 6. 種花模式：繪製各花點之覆蓋圓 (半徑 26m)，並在當前目標花點特別標示
        let isFlowerMode = (session.executionMode == 1)
        let targetFlowerIdx = isFlowerMode ? currentDisplayIdx : -1

        if context.coordinator.cachedOverlayFlowerIndex != targetFlowerIdx ||
           context.coordinator.cachedOverlayBaseCount != baseCount {
            context.coordinator.cachedOverlayFlowerIndex = targetFlowerIdx
            context.coordinator.cachedOverlayBaseCount = baseCount

            if !context.coordinator.currentCircles.isEmpty {
                mapView.removeOverlays(context.coordinator.currentCircles)
                context.coordinator.currentCircles.removeAll()
            }

            if isFlowerMode && baseCount > 0 {
                var newCircles: [MKCircle] = []
                for (i, flowerNode) in waypoints.enumerated() {
                    let centerCoord = CLLocationCoordinate2D(latitude: flowerNode.lat, longitude: flowerNode.lng)
                    if i == targetFlowerIdx {
                        let circle28 = MKCircle(center: centerCoord, radius: 28.0)
                        let circle24 = MKCircle(center: centerCoord, radius: 24.0)
                        newCircles.append(circle28)
                        newCircles.append(circle24)
                    } else {
                        let circle26 = MKCircle(center: centerCoord, radius: 26.0)
                        newCircles.append(circle26)
                    }
                }
                mapView.addOverlays(newCircles)
                context.coordinator.currentCircles = newCircles
            }
        }

        // 7. 觀測站花田圖層同步：在地圖上直接顯示印字頭花田之多邊形邊界與名牌標記
        let indiaPoints = station.allPoints.filter { $0.name.hasPrefix("印") }
        if context.coordinator.cachedStationPointsCount != indiaPoints.count ||
           context.coordinator.cachedStationLastUpdate != station.lastSyncTime {
            context.coordinator.cachedStationPointsCount = indiaPoints.count
            context.coordinator.cachedStationLastUpdate = station.lastSyncTime

            // 移除舊花田圖層
            let oldStationOverlays = mapView.overlays.filter { $0 is StationPolygon || $0 is StationCircle }
            mapView.removeOverlays(oldStationOverlays)
            let oldStationAnnotations = mapView.annotations.filter { $0 is StationBadgeAnnotation }
            mapView.removeAnnotations(oldStationAnnotations)

            var newOverlays: [MKOverlay] = []
            var newAnnotations: [MKAnnotation] = []

            for pt in indiaPoints {
                let polygonCoords = pt.polygonBoundaryCoordinates
                if polygonCoords.count >= 3 {
                    var coords = polygonCoords
                    let polygon = StationPolygon(coordinates: &coords, count: coords.count, point: pt, polygonCoordinates: polygonCoords)
                    newOverlays.append(polygon)
                } else if let coord = pt.coordinate {
                    let circle = StationCircle(center: coord, radius: 26.0, point: pt)
                    newOverlays.append(circle)
                }

                if let centerCoord = pt.centerCoordinate {
                    let badge = StationBadgeAnnotation(point: pt, coordinate: centerCoord)
                    newAnnotations.append(badge)
                }
            }

            if !newOverlays.isEmpty {
                mapView.addOverlays(newOverlays)
            }
            if !newAnnotations.isEmpty {
                mapView.addAnnotations(newAnnotations)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MainMapView
        var currentLocationAnnotation: MKPointAnnotation?
        var lastCameraCenterTrigger: Int = 0
        var lastCameraRouteBoundsTrigger: Int = 0
        var cachedRouteCount: Int = -1
        var cachedRouteName: String = ""
        var cachedCurrentIndex: Int = -1

        // 快取覆蓋層物件，杜絕每 100ms 摧毀重建 GPU 緩衝區
        var currentPolyline: MKPolyline?
        var currentCircles: [MKCircle] = []
        var cachedOverlayRouteName: String = ""
        var cachedOverlayPointsCount: Int = -1
        var cachedOverlayFlowerIndex: Int = -1
        var cachedOverlayBaseCount: Int = -1

        // 快取觀測站花田圖層
        var cachedStationPointsCount: Int = -1
        var cachedStationLastUpdate: Date? = nil

        init(_ parent: MainMapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onLongPress?(coord)
        }

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let stationPoly = overlay as? StationPolygon {
                let renderer = MKPolygonRenderer(polygon: stationPoly)
                if stationPoly.point.isCounting {
                    renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.18)
                    renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.7)
                } else {
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.18)
                    renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.7)
                }
                renderer.lineWidth = 1.5
                return renderer
            } else if let stationCircle = overlay as? StationCircle {
                let renderer = MKCircleRenderer(circle: stationCircle)
                if stationCircle.point.isCounting {
                    renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.18)
                    renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.7)
                } else {
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.18)
                    renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.7)
                }
                renderer.lineWidth = 1.5
                return renderer
            } else if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 3.5
                return renderer
            } else if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                if circle.radius >= 26.0 {
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.12)
                    renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.6)
                    renderer.lineWidth = 1.5
                } else {
                    renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.08)
                    renderer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.6)
                    renderer.lineWidth = 1.5
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 角色目前位置標記
            if let pointAnno = annotation as? MKPointAnnotation, pointAnno == currentLocationAnnotation {
                let identifier = "CurrentSimulatedLocation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                } else {
                    view?.annotation = annotation
                }
                view?.markerTintColor = .systemRed
                view?.glyphImage = UIImage(systemName: "figure.walk")
                view?.displayPriority = .required
                return view
            }

            // 觀測站花田名牌標記
            if let badge = annotation as? StationBadgeAnnotation {
                let identifier = "StationBadgeAnnotationMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                } else {
                    view?.annotation = annotation
                }
                view?.glyphText = badge.point.name.replacingOccurrences(of: "印", with: "")
                view?.markerTintColor = badge.point.isCounting ? .systemRed : .systemGreen
                view?.displayPriority = .defaultLow
                return view
            }

            // 航點數字球 (對齊安卓：花苞或航點編號 1, 2, 3...)
            if let wp = annotation as? WaypointAnnotation {
                let identifier = "WaypointAnnotationMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                } else {
                    view?.annotation = annotation
                }

                view?.glyphText = "\(wp.index + 1)"
                if wp.isTarget {
                    view?.markerTintColor = .systemOrange // 當前目標點：亮橘色
                    view?.displayPriority = .required
                } else if wp.isStart {
                    view?.markerTintColor = .systemGreen // 起點：綠色
                    view?.displayPriority = .defaultHigh
                } else {
                    view?.markerTintColor = .systemBlue // 沿途點：天藍色
                    view?.displayPriority = .defaultLow
                }
                return view
            }

            return nil
        }

        public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let pointAnno = view.annotation as? MKPointAnnotation, pointAnno == currentLocationAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onTapCurrentLocation?()
            } else if let badge = view.annotation as? StationBadgeAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectStationPoint?(badge.point)
            } else if let wp = view.annotation as? WaypointAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectWaypoint?(wp.index)
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let touchPoint = gesture.location(in: mapView)
            let touchCoord = mapView.convert(touchPoint, toCoordinateFrom: mapView)

            for overlay in mapView.overlays {
                if let polygon = overlay as? StationPolygon {
                    if pointInPolygon(point: touchCoord, polygon: polygon.polygonCoordinates) {
                        parent.onSelectStationPoint?(polygon.point)
                        return
                    }
                } else if let circle = overlay as? StationCircle {
                    let dist = EngineMath.getDistance(lat1: touchCoord.latitude, lon1: touchCoord.longitude, lat2: circle.coordinate.latitude, lon2: circle.coordinate.longitude)
                    if dist <= circle.radius {
                        parent.onSelectStationPoint?(circle.point)
                        return
                    }
                }
            }
        }

        private func pointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
            guard polygon.count >= 3 else { return false }
            var isInside = false
            var j = polygon.count - 1
            for i in 0..<polygon.count {
                if (polygon[i].longitude < point.longitude && polygon[j].longitude >= point.longitude ||
                    polygon[j].longitude < point.longitude && polygon[i].longitude >= point.longitude) {
                    if (polygon[i].latitude + (point.longitude - polygon[i].longitude) / (polygon[j].longitude - polygon[i].longitude) * (polygon[j].latitude - polygon[i].latitude) < point.latitude) {
                        isInside.toggle()
                    }
                }
                j = i
            }
            return isInside
        }
    }
}

/// 航點數字球 Annotation
public class WaypointAnnotation: NSObject, MKAnnotation {
    public let coordinate: CLLocationCoordinate2D
    public let index: Int
    public let isTarget: Bool
    public let isStart: Bool
    public let title: String?
    public let subtitle: String?

    public init(coordinate: CLLocationCoordinate2D, index: Int, isTarget: Bool, isStart: Bool, label: String? = nil, isFlower: Bool = false) {
        self.coordinate = coordinate
        self.index = index
        self.isTarget = isTarget
        self.isStart = isStart

        let prefix = isFlower ? "花苞" : "航點"
        let defaultName = "\(prefix) \(index + 1)"

        if let lbl = label, !lbl.isEmpty {
            if lbl == defaultName || lbl.contains("\(index + 1)") {
                self.title = lbl
            } else {
                self.title = "\(defaultName): \(lbl)"
            }
        } else {
            self.title = defaultName
        }

        self.subtitle = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        super.init()
    }
}
