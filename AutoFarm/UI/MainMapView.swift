import SwiftUI
import MapKit
import UIKit

public struct MainMapView: UIViewRepresentable {
    @ObservedObject var session = AutoFarmSession.shared
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onSelectWaypoint: ((Int) -> Void)?
    var onTapCurrentLocation: (() -> Void)?

    public init(
        onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
        onSelectWaypoint: ((Int) -> Void)? = nil,
        onTapCurrentLocation: (() -> Void)? = nil
    ) {
        self.onLongPress = onLongPress
        self.onSelectWaypoint = onSelectWaypoint
        self.onTapCurrentLocation = onTapCurrentLocation
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.showsCompass = true
        mapView.showsScale = true

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        mapView.addGestureRecognizer(longPress)

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
            if !session.routePoints.isEmpty {
                var zoomRect = MKMapRect.null
                for node in session.routePoints {
                    let point = MKMapPoint(CLLocationCoordinate2D(latitude: node.lat, longitude: node.lng))
                    let pointRect = MKMapRect(x: point.x, y: point.y, width: 0.1, height: 0.1)
                    zoomRect = zoomRect.union(pointRect)
                }
                let insets = UIEdgeInsets(top: 90, left: 50, bottom: 260, right: 50)
                mapView.setVisibleMapRect(zoomRect, edgePadding: insets, animated: true)
            }
        }

        // 3. 更新目前位置標記 (Simulated Character Pin)
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

        // 4. 更新航點數字球標記 (對齊安卓：起點綠色1號、沿途藍色數字、當前目標橙黃色高亮)
        let currentRouteCount = session.routePoints.count
        let currentIndex = session.currentRouteIndex
        if context.coordinator.cachedRouteCount != currentRouteCount ||
           context.coordinator.cachedRouteName != session.activeRouteName ||
           context.coordinator.cachedCurrentIndex != currentIndex {
            
            context.coordinator.cachedRouteCount = currentRouteCount
            context.coordinator.cachedRouteName = session.activeRouteName
            context.coordinator.cachedCurrentIndex = currentIndex

            // 移除舊航點標記
            let oldWaypoints = mapView.annotations.filter { $0 is WaypointAnnotation }
            mapView.removeAnnotations(oldWaypoints)

            if currentRouteCount > 0 {
                // 如果點數極多(如超過200點)，適度精簡展示以維護流暢度，但起點與目標點必保留
                let step = currentRouteCount > 200 ? max(1, currentRouteCount / 100) : 1
                var newAnnotations: [WaypointAnnotation] = []

                for i in 0..<currentRouteCount {
                    let isTarget = (i == currentIndex)
                    let isStart = (i == 0)
                    if isStart || isTarget || (i % step == 0) || (i == currentRouteCount - 1) {
                        let node = session.routePoints[i]
                        let anno = WaypointAnnotation(
                            coordinate: CLLocationCoordinate2D(latitude: node.lat, longitude: node.lng),
                            index: i,
                            isTarget: isTarget,
                            isStart: isStart,
                            label: node.label
                        )
                        newAnnotations.append(anno)
                    }
                }
                mapView.addAnnotations(newAnnotations)
            }
        }

        // 5. 更新路線連線軌跡 (Polyline)
        mapView.removeOverlays(mapView.overlays)
        if session.routePoints.count > 1 {
            let coords = session.routePoints.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            mapView.addOverlay(polyline)
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
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 4.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 角色當前位置標記
            if let pointAnno = annotation as? MKPointAnnotation, pointAnno == currentLocationAnnotation {
                let identifier = "CurrentSimulatedLocation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = annotation
                }
                view?.markerTintColor = .systemRed
                view?.glyphImage = UIImage(systemName: "figure.walk")
                view?.displayPriority = .required
                return view
            }

            // 航點數字球 (對齊安卓版本)
            if let wp = annotation as? WaypointAnnotation {
                let identifier = "WaypointAnnotationMarker"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                if view == nil {
                    view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
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
            } else if let wp = view.annotation as? WaypointAnnotation {
                mapView.deselectAnnotation(view.annotation, animated: false)
                parent.onSelectWaypoint?(wp.index)
            }
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

    public init(coordinate: CLLocationCoordinate2D, index: Int, isTarget: Bool, isStart: Bool, label: String? = nil) {
        self.coordinate = coordinate
        self.index = index
        self.isTarget = isTarget
        self.isStart = isStart
        let numStr = "航點 \(index + 1)"
        if let lbl = label, !lbl.isEmpty {
            self.title = "\(numStr): \(lbl)"
        } else {
            self.title = numStr
        }
        self.subtitle = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        super.init()
    }
}
