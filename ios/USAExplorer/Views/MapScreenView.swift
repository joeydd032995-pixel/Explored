import SwiftUI
import MapKit

struct MapScreenView: UIViewRepresentable {
    let userLocation: CLLocationCoordinate2D?
    let travelPath: [CLLocationCoordinate2D]
    let fogPolygons: [FogHexPolygon]
    var glowCircles: [FogGlowCircle] = []
    var overlayFeatures: [OverlayFeature] = []
    var onFeatureTap: (OverlayFeature) -> Void = { _ in }
    let onRegionChanged: (MKCoordinateRegion) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    private let darkNavy = UIColor(red: 10/255, green: 15/255, blue: 30/255, alpha: 1)
    private let gold = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.overrideUserInterfaceStyle = .dark
        mapView.pointOfInterestFilter = .excludingAll

        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .muted
        mapView.preferredConfiguration = config

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 50)
        )
        mapView.setRegion(region, animated: false)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: longPress)
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    /// Rebuilding thousands of fog polygons on every SwiftUI update was the
    /// app's biggest lag source — diff each content group and touch the map
    /// only when that group actually changed.
    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.currentFogPolygons = fogPolygons
        context.coordinator.currentTravelPath = travelPath
        context.coordinator.currentUserLocation = userLocation
        context.coordinator.currentOverlayFeatures = overlayFeatures
        context.coordinator.onFeatureTap = onFeatureTap
        context.coordinator.onLongPress = onLongPress

        // Hex layer: rebuild only when the polygon set changed.
        let hexKeys = fogPolygons.map(\.id)
        if hexKeys != context.coordinator.appliedHexKeys {
            context.coordinator.appliedHexKeys = hexKeys
            let hexOverlays = mapView.overlays.filter { $0 is MKPolygon }
            if !hexOverlays.isEmpty { mapView.removeOverlays(hexOverlays) }
            for fog in fogPolygons {
                var coords = fog.coordinates
                let polygon = MKPolygon(coordinates: &coords, count: coords.count)
                polygon.title = fog.kind.rawValue
                mapView.addOverlay(polygon, level: .aboveRoads)
            }
        }

        // Discovered-glow circles: rebuild only when the set changed.
        let circleIds = glowCircles.map(\.id)
        if circleIds != context.coordinator.appliedGlowCircleIds {
            context.coordinator.appliedGlowCircleIds = circleIds
            let circleOverlays = mapView.overlays.filter { ($0 as? MKCircle)?.title == FogPolygonKind.discoveredGlow.rawValue }
            if !circleOverlays.isEmpty { mapView.removeOverlays(circleOverlays) }
            for glow in glowCircles {
                let circle = MKCircle(center: glow.center, radius: glow.radius)
                circle.title = FogPolygonKind.discoveredGlow.rawValue
                mapView.addOverlay(circle, level: .aboveRoads)
            }
        }

        // Travel path: rebuild only when points were added.
        if travelPath.count != context.coordinator.appliedPathCount {
            context.coordinator.appliedPathCount = travelPath.count
            let lines = mapView.overlays.filter { $0 is MKPolyline }
            if !lines.isEmpty { mapView.removeOverlays(lines) }
            if travelPath.count >= 2 {
                let polyline = MKPolyline(coordinates: travelPath, count: travelPath.count)
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
        }

        // Annotations: rebuild only when features or the user dot moved.
        let featureIds = overlayFeatures.map(\.id)
        let appliedUser = context.coordinator.appliedUserLocation
        let userMoved = userLocation?.latitude != appliedUser?.latitude
            || userLocation?.longitude != appliedUser?.longitude
        if featureIds != context.coordinator.appliedFeatureIds || userMoved {
            context.coordinator.appliedFeatureIds = featureIds
            context.coordinator.appliedUserLocation = userLocation
            mapView.removeAnnotations(mapView.annotations)

            if let location = userLocation {
                let annotation = MKPointAnnotation()
                annotation.coordinate = location
                annotation.title = "current_location"
                mapView.addAnnotation(annotation)
            }

            for feature in overlayFeatures {
                let annotation = OverlayPointAnnotation()
                annotation.coordinate = feature.coordinate
                annotation.title = "overlay_feature"
                annotation.featureId = feature.id
                annotation.kindRaw = feature.kind.rawValue
                mapView.addAnnotation(annotation)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(gold: gold, onRegionChanged: onRegionChanged, onLongPress: onLongPress)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let gold: UIColor
        let onRegionChanged: (MKCoordinateRegion) -> Void
        var onLongPress: (CLLocationCoordinate2D) -> Void
        var currentFogPolygons: [FogHexPolygon] = []
        var currentTravelPath: [CLLocationCoordinate2D] = []
        var currentUserLocation: CLLocationCoordinate2D?
        var currentOverlayFeatures: [OverlayFeature] = []
        var onFeatureTap: (OverlayFeature) -> Void = { _ in }
        var appliedHexKeys: [String] = []
        var appliedGlowCircleIds: [String] = []
        var appliedPathCount = -1
        var appliedFeatureIds: [String] = []
        var appliedUserLocation: CLLocationCoordinate2D?

        init(gold: UIColor, onRegionChanged: @escaping (MKCoordinateRegion) -> Void, onLongPress: @escaping (CLLocationCoordinate2D) -> Void) {
            self.gold = gold
            self.onRegionChanged = onRegionChanged
            self.onLongPress = onLongPress
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)

            for annotation in mapView.annotations {
                guard let annotationView = mapView.view(for: annotation),
                      annotationView.frame.contains(point),
                      let overlayAnnotation = annotation as? OverlayPointAnnotation else { continue }
                guard let feature = currentOverlayFeatures.first(where: { $0.id == overlayAnnotation.featureId }) else { continue }
                Task { @MainActor in
                    onFeatureTap(feature)
                }
                return
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            Task { @MainActor in
                onLongPress(coordinate)
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            Task { @MainActor in
                onRegionChanged(region)
            }
        }

        nonisolated func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle, circle.title == FogPolygonKind.discoveredGlow.rawValue {
                let renderer = MKCircleRenderer(overlay: circle)
                // Soft gold halo marking territory already explored.
                renderer.fillColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 0.16)
                renderer.strokeColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 0.35)
                renderer.lineWidth = 1
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(overlay: polygon)
                if polygon.title == FogPolygonKind.discovered.rawValue {
                    // Territory marker: discovered cells glow gold — the map
                    // lights up as you explore.
                    renderer.fillColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 0.5)
                    renderer.strokeColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 0.9)
                    renderer.lineWidth = 1
                } else if polygon.title == FogPolygonKind.discoveredGlow.rawValue {
                    // Zoomed-out glow over the parent region of discoveries;
                    // resolves into exact gold hexes as the user zooms in.
                    renderer.fillColor = UIColor.red.withAlphaComponent(0.85)
                    renderer.strokeColor = UIColor.yellow
                    renderer.lineWidth = 2
                } else {
                    // Fog of war: undiscovered hexes recede into a dark navy haze
                    // (alarm-red read as an error blanket when nothing is explored yet).
                    renderer.fillColor = UIColor(red: 10/255, green: 15/255, blue: 30/255, alpha: 0.55)
                    renderer.strokeColor = nil
                    renderer.lineWidth = 0
                }
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(overlay: polyline)
                renderer.strokeColor = UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        nonisolated func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation.title == "current_location" else {
                if let overlayAnnotation = annotation as? OverlayPointAnnotation {
                    let identifier = "OverlayFeature"
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                        ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                    view.annotation = annotation
                    view.canShowCallout = false
                    view.collisionMode = .circle
                    view.image = OverlayAnnotationRenderer.image(forRawKind: overlayAnnotation.kindRaw)
                    return view
                }
                return nil
            }

            let identifier = "UserDot"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)

            view.annotation = annotation
            view.canShowCallout = false

            let size: CGFloat = 18
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
            view.image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 2.5, y: 2.5, width: size - 5, height: size - 5))
            }

            return view
        }
    }
}

// MARK: - Overlay Annotations

// Hex polygons are plain MKPolygons tagged with the hex layer kind
// (title = FogPolygonKind) so the renderer can style fog vs discovered
// without ambiguity. MKPolygon is not subclassed: its coordinate factory
// initializers do not populate subclasses' storage.

nonisolated final class OverlayPointAnnotation: MKPointAnnotation {
    var featureId: String = ""
    var kindRaw: String = ""
}

nonisolated enum OverlayAnnotationRenderer {
    private static func color(forRawKind rawKind: String) -> UIColor {
        switch OverlayFeatureKind(rawValue: rawKind) {
        case .alprFixed, .alprMobile: return UIColor(red: 0.90, green: 0.27, blue: 0.27, alpha: 1)
        case .tollGantry: return UIColor(red: 0.96, green: 0.77, blue: 0.10, alpha: 1)
        case .redLight: return UIColor(red: 0.85, green: 0.35, blue: 0.85, alpha: 1)
        case .police: return UIColor(red: 0.20, green: 0.62, blue: 0.94, alpha: 1)
        case .speedTrap: return UIColor(red: 0.94, green: 0.50, blue: 0.10, alpha: 1)
        case .accident: return UIColor(red: 0.94, green: 0.28, blue: 0.28, alpha: 1)
        case .roadHazard: return UIColor(red: 0.98, green: 0.68, blue: 0.15, alpha: 1)
        case .construction: return UIColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1)
        case .custom: return UIColor(red: 245/255, green: 197/255, blue: 24/255, alpha: 1)
        case nil: return UIColor.white
        }
    }

    static func image(forRawKind rawKind: String) -> UIImage {
        let size = CGSize(width: 26, height: 26)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let color = color(forRawKind: rawKind)

            UIColor.black.withAlphaComponent(0.35).setFill()
            ctx.cgContext.fillEllipse(in: rect.insetBy(dx: -2, dy: -2))

            color.setFill()
            ctx.cgContext.fillEllipse(in: rect)

            UIColor.white.withAlphaComponent(0.9).setStroke()
            ctx.cgContext.setLineWidth(1.5)
            ctx.cgContext.strokeEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
        }
    }
}
