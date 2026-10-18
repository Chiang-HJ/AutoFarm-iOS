import SwiftUI
import MapKit
import UIKit

public struct MainMapView: UIViewRepresentable {
    @ObservedObject var session = AutoFarmSession.shared
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onSelectWaypoint: ((Int) -> Void)?

    public init(
        onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
        onSelectWaypoint: ((Int) -> Void)? = nil
    ) {
        self.onLongPress = onLongPress
        self.onSelectWaypoint = onSelectWaypoint
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

        // 1. 更新當前位置標記 (Simulated Location Pin)
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

        // 2. 更新路線軌跡 (Polyline)
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
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }

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
            return view
        }
    }
}
