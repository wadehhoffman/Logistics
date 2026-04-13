import SwiftUI
import MapKit

/// UIViewRepresentable MKMapView for the Today dispatcher dashboard.
///
/// Why UIKit instead of SwiftUI Map: vehicle clustering needs
/// MKClusterAnnotation + a clusteringIdentifier on the annotation view,
/// neither of which is exposed by SwiftUI's Map in iOS 17. The rest of
/// the dashboard stays in SwiftUI — only this one view drops down to
/// UIKit.
///
/// Overlays:
///   - one StatusPolyline per route (mill ↔ yard), color-coded
///   - one RouteEndpointAnnotation for each mill and yard
///   - one VehicleAnnotation per live vehicle (clusters automatically)
///
/// Interactions:
///   - Tap a cluster bubble → ClusterDetailSheet shows via
///     `selectedClusterVehicles` binding on the parent
///   - `focusRouteId` binding fits the map to a specific route
///   - `focusVehicleId` binding pans to a vehicle and opens its callout
struct TodayMapView: UIViewRepresentable {
    @Environment(LocationDataStore.self) private var dataStore

    let routes: [ScheduledRoute]
    let vehicles: [Vehicle]

    @Binding var focusRouteId: String?
    @Binding var focusVehicleId: Int?
    @Binding var selectedClusterVehicles: [Vehicle]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.5, longitude: -82.5),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 15)
        ), animated: false)

        // Register annotation view classes for clustering
        map.register(VehicleAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: VehicleAnnotationView.reuseID)
        map.register(VehicleClusterView.self,
                     forAnnotationViewWithReuseIdentifier: VehicleClusterView.reuseID)
        map.register(EndpointAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: EndpointAnnotationView.reuseID)

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.sync(mapView: mapView,
                                 routes: routes,
                                 vehicles: vehicles,
                                 dataStore: dataStore)

        // Focus changes are one-shot: apply and clear
        if let id = focusRouteId {
            context.coordinator.focusRoute(id: id, mapView: mapView, dataStore: dataStore)
            DispatchQueue.main.async { self.focusRouteId = nil }
        }
        if let id = focusVehicleId {
            context.coordinator.focusVehicle(id: id, mapView: mapView)
            DispatchQueue.main.async { self.focusVehicleId = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: TodayMapView

        // Keep the most recent inputs so we can diff and skip unnecessary work
        private var lastRouteSignature: String = ""
        private var lastVehicleIds: Set<Int> = []
        private var hasFit: Bool = false

        init(parent: TodayMapView) { self.parent = parent }

        // MARK: Sync

        func sync(mapView: MKMapView,
                  routes: [ScheduledRoute],
                  vehicles: [Vehicle],
                  dataStore: LocationDataStore) {
            let routeSig = routes.map { "\($0.id):\($0.status)" }.joined(separator: ",")
            let vehicleIds = Set(vehicles.map(\.id))

            // Rebuild route overlays + endpoint annotations if routes changed
            if routeSig != lastRouteSignature {
                lastRouteSignature = routeSig
                mapView.removeOverlays(mapView.overlays)
                let endpointAnnos = mapView.annotations.compactMap { $0 as? RouteEndpointAnnotation }
                mapView.removeAnnotations(endpointAnnos)

                for route in routes {
                    guard let mill = resolveMill(route: route, dataStore: dataStore),
                          let yard = resolveYard(route: route, dataStore: dataStore),
                          let millCoord = mill.coordinate else { continue }
                    let yardCoord = yard.coordinate

                    let line = StatusPolyline(coordinates: [millCoord, yardCoord], count: 2)
                    line.strokeColor = statusColor(route.statusEnum)
                    line.isCancelled = route.statusEnum == .cancelled
                    mapView.addOverlay(line)

                    mapView.addAnnotation(RouteEndpointAnnotation(
                        kind: .mill, coordinate: millCoord,
                        title: "🏭 \(mill.name)"
                    ))
                    mapView.addAnnotation(RouteEndpointAnnotation(
                        kind: .yard, coordinate: yardCoord,
                        title: "🏪 \(yard.displayName)"
                    ))
                }
            }

            // Rebuild vehicle annotations if the set of vehicle IDs changed
            // OR position-bearing fields changed. We detect the former cheaply;
            // for position updates, always refresh so markers move.
            let existingVehicleAnnos = mapView.annotations.compactMap { $0 as? VehicleAnnotation }
            let existingIds = Set(existingVehicleAnnos.map { $0.vehicle.id })
            let positionsChanged = vehicles.contains { v in
                guard let existing = existingVehicleAnnos.first(where: { $0.vehicle.id == v.id }) else { return true }
                return existing.vehicle.lat != v.lat || existing.vehicle.lon != v.lon
            }

            if vehicleIds != existingIds || positionsChanged {
                mapView.removeAnnotations(existingVehicleAnnos)
                for v in vehicles where v.lat != 0 && v.lon != 0 {
                    mapView.addAnnotation(VehicleAnnotation(vehicle: v))
                }
                lastVehicleIds = vehicleIds
            }

            // Initial fit-to-content once enough data has arrived
            if !hasFit && (!routes.isEmpty || !vehicles.isEmpty) {
                fitAll(mapView: mapView)
                hasFit = true
            }
        }

        // MARK: Focus

        func focusRoute(id: String, mapView: MKMapView, dataStore: LocationDataStore) {
            guard let route = parent.routes.first(where: { $0.id == id }),
                  let mill = resolveMill(route: route, dataStore: dataStore),
                  let yard = resolveYard(route: route, dataStore: dataStore),
                  let millCoord = mill.coordinate else { return }
            let region = region(enclosing: [millCoord, yard.coordinate], padding: 1.4, minSpan: 0.3)
            mapView.setRegion(region, animated: true)
        }

        func focusVehicle(id: Int, mapView: MKMapView) {
            guard let v = parent.vehicles.first(where: { $0.id == id }) else { return }
            mapView.setRegion(MKCoordinateRegion(
                center: v.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
            ), animated: true)
            if let anno = mapView.annotations.compactMap({ $0 as? VehicleAnnotation })
                .first(where: { $0.vehicle.id == id }) {
                mapView.selectAnnotation(anno, animated: true)
            }
        }

        // MARK: Fit

        func fitAll(mapView: MKMapView) {
            var coords: [CLLocationCoordinate2D] = []
            for anno in mapView.annotations {
                if let v = anno as? VehicleAnnotation { coords.append(v.coordinate) }
                if let e = anno as? RouteEndpointAnnotation { coords.append(e.coordinate) }
            }
            guard !coords.isEmpty else { return }
            mapView.setRegion(region(enclosing: coords, padding: 1.3, minSpan: 0.5), animated: false)
        }

        private func region(enclosing coords: [CLLocationCoordinate2D],
                            padding: Double,
                            minSpan: Double) -> MKCoordinateRegion {
            let lats = coords.map(\.latitude)
            let lons = coords.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let latDelta = max(minSpan, (maxLat - minLat) * padding)
            let lonDelta = max(minSpan, (maxLon - minLon) * padding)
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            )
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? StatusPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = line.strokeColor
                renderer.lineWidth = 3
                if line.isCancelled { renderer.lineDashPattern = [6, 4] }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: VehicleClusterView.reuseID, for: annotation)
            }
            if annotation is VehicleAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: VehicleAnnotationView.reuseID, for: annotation)
            }
            if annotation is RouteEndpointAnnotation {
                return mapView.dequeueReusableAnnotationView(
                    withIdentifier: EndpointAnnotationView.reuseID, for: annotation)
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let vehicles = cluster.memberAnnotations
                    .compactMap { ($0 as? VehicleAnnotation)?.vehicle }
                mapView.deselectAnnotation(cluster, animated: false)
                DispatchQueue.main.async { self.parent.selectedClusterVehicles = vehicles }
            }
        }

        // MARK: - Helpers

        private func statusColor(_ status: ScheduledRoute.Status) -> UIColor {
            switch status {
            case .scheduled:             return .systemBlue
            case .inProgress:            return .systemOrange
            case .delivered, .completed: return .systemGreen
            case .cancelled:             return .systemRed
            }
        }

        private func resolveMill(route: ScheduledRoute, dataStore: LocationDataStore) -> Mill? {
            guard let m = route.mill else { return nil }
            if let uuid = m.uuid, let match = dataStore.mills.first(where: { $0.uuid == uuid }) { return match }
            return dataStore.mills.first { $0.name == m.name }
        }

        private func resolveYard(route: ScheduledRoute, dataStore: LocationDataStore) -> Yard? {
            guard let y = route.yard else { return nil }
            if let uuid = y.uuid, let match = dataStore.yards.first(where: { $0.uuid == uuid }) { return match }
            if let pos = y.posNumber, let match = dataStore.yards.first(where: { $0.posNumber == pos }) { return match }
            return nil
        }
    }
}

// MARK: - Annotation Views

/// Single-vehicle marker. `clusteringIdentifier` lets MapKit group nearby
/// instances automatically; it unclusters as the user zooms in.
final class VehicleAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "vehicle"

    override var annotation: MKAnnotation? {
        willSet {
            clusteringIdentifier = "vehicles"
            guard let vehicle = (newValue as? VehicleAnnotation)?.vehicle else { return }
            markerTintColor = color(for: vehicle)
            glyphImage = UIImage(systemName: vehicle.type.systemImage)
            displayPriority = .defaultLow
            canShowCallout = true
        }
    }

    private func color(for vehicle: Vehicle) -> UIColor {
        switch vehicle.status {
        case .moving:  return .systemBlue
        case .idle:    return .systemOrange
        case .stopped: return .systemRed
        }
    }
}

/// Cluster bubble shown in place of overlapping vehicles. Color reflects
/// the dominant status (moving > idle > off). Number of vehicles shown
/// as the glyph text.
final class VehicleClusterView: MKMarkerAnnotationView {
    static let reuseID = "vehicle-cluster"

    override var annotation: MKAnnotation? {
        willSet {
            guard let cluster = newValue as? MKClusterAnnotation else { return }
            let vehicles = cluster.memberAnnotations.compactMap { ($0 as? VehicleAnnotation)?.vehicle }
            let moving  = vehicles.filter { $0.status == .moving  }.count
            let idling  = vehicles.filter { $0.status == .idle    }.count
            markerTintColor = moving > 0 ? .systemBlue : idling > 0 ? .systemOrange : .systemRed
            glyphText = "\(vehicles.count)"
            displayPriority = .required
            canShowCallout = false   // we present our own sheet instead
            collisionMode = .circle
        }
    }
}

/// Small circle pin for mill/yard route endpoints. Red = mill, blue = yard.
final class EndpointAnnotationView: MKMarkerAnnotationView {
    static let reuseID = "endpoint"

    override var annotation: MKAnnotation? {
        willSet {
            guard let endpoint = newValue as? RouteEndpointAnnotation else { return }
            switch endpoint.kind {
            case .mill:
                markerTintColor = .systemRed
                glyphImage = UIImage(systemName: "building.2.fill")
            case .yard:
                markerTintColor = .systemBlue
                glyphImage = UIImage(systemName: "house.fill")
            }
            displayPriority = .defaultHigh
            canShowCallout = true
        }
    }
}
