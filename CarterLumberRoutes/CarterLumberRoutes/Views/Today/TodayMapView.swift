import SwiftUI
import MapKit

/// Compact map for the Today tab.
///
/// Shows:
///   - A straight-line polyline per scheduled route (mill ↔ yard) colored
///     by status. Status-colored markers at each endpoint.
///   - All live vehicle markers, colored by status (moving / idle / off).
///
/// Mills are looked up in LocationDataStore by uuid (preferred) or name.
/// Yards are looked up by uuid or posNumber. Mills without coordinates are
/// silently skipped — the Geocode-missing action in Settings backfills them.
///
/// Phase iH will replace this with an MKClusterAnnotation-based version so
/// overlapping vehicles at one yard collapse into a count bubble.
struct TodayMapView: View {
    @Environment(LocationDataStore.self) private var dataStore
    let routes: [ScheduledRoute]
    let vehicles: [Vehicle]

    /// Allow parent to request a re-fit when the selected route / vehicle changes.
    @Binding var focusRouteId: String?
    @Binding var focusVehicleId: Int?

    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.5, longitude: -82.5),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 15)
    )

    var body: some View {
        Map(position: $cameraPosition) {
            // Route lines + endpoint pins
            ForEach(Array(routes.enumerated()), id: \.element.id) { _, route in
                if let pair = resolveEndpoints(for: route) {
                    MapPolyline(coordinates: [pair.millCoord, pair.yardCoord])
                        .stroke(color(for: route.statusEnum), lineWidth: 3)
                    Annotation("🏭 \(pair.millName)", coordinate: pair.millCoord) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    Annotation("🏪 \(pair.yardLabel)", coordinate: pair.yardCoord) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            // Vehicle markers
            ForEach(vehicles) { vehicle in
                Annotation(vehicleLabel(vehicle), coordinate: vehicle.coordinate) {
                    vehiclePin(for: vehicle)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .onChange(of: routes.map(\.id)) { _, _ in fitToContent() }
        .onChange(of: vehicles.count) { _, _ in
            // Only auto-fit on the very first vehicle load, not every refresh
            if routes.isEmpty && !vehicles.isEmpty { fitToContent() }
        }
        .onChange(of: focusRouteId) { _, newVal in
            if let id = newVal, let route = routes.first(where: { $0.id == id }),
               let pair = resolveEndpoints(for: route) {
                zoom(to: [pair.millCoord, pair.yardCoord])
            }
        }
        .onChange(of: focusVehicleId) { _, newVal in
            if let id = newVal, let v = vehicles.first(where: { $0.id == id }) {
                zoom(to: [v.coordinate], span: 0.2)
            }
        }
        .task(id: routes.map(\.id).joined()) { fitToContent() }
    }

    // MARK: - Endpoint resolution

    private struct EndpointPair {
        let millCoord: CLLocationCoordinate2D
        let yardCoord: CLLocationCoordinate2D
        let millName: String
        let yardLabel: String
    }

    private func resolveEndpoints(for route: ScheduledRoute) -> EndpointPair? {
        let mill = findMill(for: route)
        let yard = findYard(for: route)
        guard let mill, let yard,
              let millCoord = mill.coordinate,
              yard.lat != 0, yard.lon != 0 else { return nil }
        return EndpointPair(
            millCoord: millCoord,
            yardCoord: yard.coordinate,
            millName: mill.name,
            yardLabel: yard.displayName
        )
    }

    private func findMill(for route: ScheduledRoute) -> Mill? {
        guard let m = route.mill else { return nil }
        if let uuid = m.uuid, let match = dataStore.mills.first(where: { $0.uuid == uuid }) { return match }
        return dataStore.mills.first { $0.name == m.name }
    }

    private func findYard(for route: ScheduledRoute) -> Yard? {
        guard let y = route.yard else { return nil }
        if let uuid = y.uuid, let match = dataStore.yards.first(where: { $0.uuid == uuid }) { return match }
        if let pos = y.posNumber, let match = dataStore.yards.first(where: { $0.posNumber == pos }) { return match }
        return nil
    }

    // MARK: - Visual helpers

    private func color(for status: ScheduledRoute.Status) -> Color {
        switch status {
        case .scheduled:             return .blue
        case .inProgress:            return .orange
        case .delivered, .completed: return .green
        case .cancelled:             return .red
        }
    }

    private func vehicleLabel(_ v: Vehicle) -> String {
        let op = v.operatorOrDriver
        return op.isEmpty ? v.name : "\(v.name) – \(op)"
    }

    @ViewBuilder
    private func vehiclePin(for v: Vehicle) -> some View {
        let color: Color = {
            switch v.status {
            case .moving:  return .blue
            case .idle:    return .orange
            case .stopped: return .red
            }
        }()
        let symbol = v.type.systemImage
        ZStack {
            RoundedRectangle(cornerRadius: v.type == .trailer ? 3 : 6)
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: v.type == .trailer ? 3 : 6)
                        .stroke(v.type == .trailer ? Color.yellow.opacity(0.85) : .white,
                                style: StrokeStyle(lineWidth: 2, dash: v.type == .trailer ? [3] : []))
                )
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(radius: 2)
    }

    // MARK: - Camera

    private func fitToContent() {
        var coords: [CLLocationCoordinate2D] = []
        for route in routes {
            if let pair = resolveEndpoints(for: route) {
                coords.append(pair.millCoord)
                coords.append(pair.yardCoord)
            }
        }
        for v in vehicles where v.lat != 0 && v.lon != 0 {
            coords.append(v.coordinate)
        }
        guard !coords.isEmpty else { return }
        zoom(to: coords)
    }

    private func zoom(to coords: [CLLocationCoordinate2D], span: Double = 0) {
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            let effectiveSpan = span > 0 ? span : 0.5
            cameraPosition = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: effectiveSpan, longitudeDelta: effectiveSpan)
            ))
            return
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Padding so markers aren't cropped at the edges
        let latDelta = max(0.3, (maxLat - minLat) * 1.4)
        let lonDelta = max(0.3, (maxLon - minLon) * 1.4)
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }
}
