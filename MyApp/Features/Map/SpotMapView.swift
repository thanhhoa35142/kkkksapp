import MapKit
import SwiftUI

/// MKMapView wrapper — SwiftUI `Map` can't cluster on iOS 17 / macOS 14, so
/// pins go through MKMarkerAnnotationView with a clustering identifier
/// (UI_SPEC S2). One coordinator for UIKit and AppKit.
struct SpotMapView {
    var pins: [MapPin]
    var outlines: [UUID: JSONValue]
    var selection: UUID?
    var focus: MapFocus?
    var onSelect: (UUID?) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void
    var onUserPan: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    fileprivate func makeMap(_ coordinator: Coordinator) -> MKMapView {
        let map = MKMapView()
        map.delegate = coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: Coordinator.spotReuseID)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: Coordinator.clusterReuseID)
        #if os(iOS)
        map.showsCompass = true
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.userPanned(_:)))
        pan.delegate = coordinator
        map.addGestureRecognizer(pan)
        #endif
        return map
    }

    fileprivate func update(_ map: MKMapView, _ coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.sync(pins: pins, on: map)
        coordinator.sync(outlines: outlines, on: map)
        coordinator.sync(selection: selection, on: map)
        coordinator.apply(focus: focus, on: map)
    }
}

/// Request to move the camera (place change, sidebar selection, deep link).
struct MapFocus: Equatable {
    let version: Int
    let latitude: Double
    let longitude: Double
    let span: Double
}

#if os(iOS)
extension SpotMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateUIView(_ map: MKMapView, context: Context) { update(map, context.coordinator) }
}
#elseif os(macOS)
extension SpotMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> MKMapView { makeMap(context.coordinator) }
    func updateNSView(_ map: MKMapView, context: Context) { update(map, context.coordinator) }
}
#endif

extension SpotMapView {
    final class SpotAnnotation: NSObject, MKAnnotation {
        let id: UUID
        @objc dynamic var coordinate: CLLocationCoordinate2D
        var title: String?
        var score: Int?
        var capReason: String?

        init(_ pin: MapPin) {
            id = pin.id
            coordinate = pin.coordinate
            title = pin.title
            score = pin.score
            capReason = pin.capReason
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let spotReuseID = "spot"
        static let clusterReuseID = "cluster"

        var parent: SpotMapView
        private var annotations: [UUID: SpotAnnotation] = [:]
        private var overlays: [UUID: MKMultiPolygon] = [:]
        private var lastFocusVersion: Int?
        private var applyingSelection = false

        init(parent: SpotMapView) { self.parent = parent }

        // MARK: Sync from SwiftUI

        func sync(pins: [MapPin], on map: MKMapView) {
            let incoming = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let removed = annotations.keys.filter { incoming[$0] == nil }
            map.removeAnnotations(removed.compactMap { annotations.removeValue(forKey: $0) })

            var added: [SpotAnnotation] = []
            for pin in pins {
                if let existing = annotations[pin.id] {
                    guard existing.score != pin.score || existing.capReason != pin.capReason
                            || existing.title != pin.title else { continue }
                    existing.score = pin.score
                    existing.capReason = pin.capReason
                    existing.title = pin.title
                    if let view = map.view(for: existing) as? MKMarkerAnnotationView {
                        Self.style(view, for: existing)
                    }
                } else {
                    let annotation = SpotAnnotation(pin)
                    annotations[pin.id] = annotation
                    added.append(annotation)
                }
            }
            map.addAnnotations(added)
        }

        func sync(outlines: [UUID: JSONValue], on map: MKMapView) {
            let removed = overlays.keys.filter { outlines[$0] == nil }
            map.removeOverlays(removed.compactMap { overlays.removeValue(forKey: $0) })
            for (id, area) in outlines where overlays[id] == nil {
                guard let shape = GeoJSONArea.multiPolygon(area) else { continue }
                overlays[id] = shape
                map.addOverlay(shape, level: .aboveRoads)
            }
        }

        func sync(selection: UUID?, on map: MKMapView) {
            let current = (map.selectedAnnotations.first as? SpotAnnotation)?.id
            guard current != selection else { return }
            applyingSelection = true
            defer { applyingSelection = false }
            if let selection, let annotation = annotations[selection] {
                map.selectAnnotation(annotation, animated: true)
            } else {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
            }
        }

        func apply(focus: MapFocus?, on map: MKMapView) {
            guard let focus, focus.version != lastFocusVersion else { return }
            let isFirst = lastFocusVersion == nil
            lastFocusVersion = focus.version
            let center = CLLocationCoordinate2D(latitude: focus.latitude, longitude: focus.longitude)
            // Don't jump if the target is already on screen (selection from the map itself).
            if !isFirst, map.visibleMapRect.contains(MKMapPoint(center)),
               map.region.span.latitudeDelta <= focus.span * 4 { return }
            let region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: focus.span, longitudeDelta: focus.span))
            map.setRegion(region, animated: !isFirst && !Self.reduceMotion)
        }

        // MARK: Delegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: Self.clusterReuseID, for: cluster) as? MKMarkerAnnotationView
                view?.markerTintColor = .brand
                view?.glyphText = "\(cluster.memberAnnotations.count)"
                view?.titleVisibility = .hidden
                view?.subtitleVisibility = .hidden
                return view
            }
            guard let spot = annotation as? SpotAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.spotReuseID, for: spot) as? MKMarkerAnnotationView
            view?.clusteringIdentifier = "spot"
            if let view { Self.style(view, for: spot) }
            return view
        }

        static func style(_ view: MKMarkerAnnotationView, for spot: SpotAnnotation) {
            if let score = spot.score {
                let tier = ScoreTier(score: score)
                view.glyphText = "\(score)"
                view.markerTintColor = tier.platformColor
                view.displayPriority = score >= 60 ? .defaultHigh : .defaultLow
            } else {
                view.glyphText = "–"
                view.markerTintColor = .systemGray
                view.displayPriority = .defaultLow
            }
            view.titleVisibility = .adaptive
            let label = [spot.title, spot.score.map { String(localized: "score \($0)") }]
                .compactMap { $0 }.joined(separator: ", ")
            #if os(iOS)
            view.accessibilityLabel = label
            #else
            view.setAccessibilityLabel(label)
            #endif
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let shape = overlay as? MKMultiPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolygonRenderer(multiPolygon: shape)
            renderer.fillColor = PlatformColor.brand.withAlphaComponent(0.15)
            renderer.strokeColor = .brand
            renderer.lineWidth = 1.5
            return renderer
        }

        // The MKAnnotationView variants exist on iOS and macOS; the
        // `didSelect annotation:` ones are unavailable on macOS.
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: !Self.reduceMotion)
                mapView.deselectAnnotation(cluster, animated: false)
                return
            }
            guard !applyingSelection, let spot = annotation as? SpotAnnotation else { return }
            parent.onSelect(spot.id)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            guard !applyingSelection, view.annotation is SpotAnnotation else { return }
            // Selecting another pin fires deselect first; only clear when nothing is selected.
            DispatchQueue.main.async { [weak self, weak mapView] in
                guard let self, let mapView, mapView.selectedAnnotations.isEmpty else { return }
                self.parent.onSelect(nil)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mapView.region)
        }

        #if os(iOS)
        @objc func userPanned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { parent.onUserPan() }
        }
        #endif

        static var reduceMotion: Bool {
            #if os(iOS)
            UIAccessibility.isReduceMotionEnabled
            #else
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #endif
        }
    }
}

#if os(iOS)
extension SpotMapView.Coordinator: UIGestureRecognizerDelegate {
    /// Observe pans alongside MapKit's own recognizers.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
