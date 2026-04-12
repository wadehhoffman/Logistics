import SwiftUI
import MapKit
import CoreLocation

/// Map view using Apple MapKit as a fallback.
/// When Mapbox SDK is added via SPM, replace this with UIViewRepresentable wrapping MapboxMaps.MapView.
struct MapContainerView: View {
    let routeCoordinates: [[Double]]
    let annotations: [MapViewModel.MapAnnotation]
    let isFallbackRoute: Bool
    let showTrafficLayer: Bool

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition) {
            // Route polyline
            if !routeCoordinates.isEmpty {
                let coords = routeCoordinates.map {
                    CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
                }
                MapPolyline(coordinates: coords)
                    .stroke(
                        isFallbackRoute ? Color.orange : Color(red: 0.17, green: 0.37, blue: 0.54),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round,
                                           dash: isFallbackRoute ? [8, 6] : [])
                    )
            }

            // Annotations
            ForEach(annotations) { annotation in
                Annotation(annotation.title, coordinate: annotation.coordinate) {
                    annotationView(for: annotation)
                }
            }
        }
        .mapStyle(showTrafficLayer ? .standard(pointsOfInterest: .excludingAll, showsTraffic: true) : .standard)
        .onChange(of: routeCoordinates) {
            fitToRoute()
        }
        .onChange(of: annotations.count) {
            fitToRoute()
        }
    }

    @ViewBuilder
    private func annotationView(for annotation: MapViewModel.MapAnnotation) -> some View {
        switch annotation.type {
        case .mill:
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 28, height: 28)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        case .yard:
            ZStack {
                Circle()
                    .fill(Color(red: 0.17, green: 0.37, blue: 0.54))
                    .frame(width: 28, height: 28)
                Image(systemName: "house.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
        case .truckMoving:
            truckMarker(color: .blue)
        case .truckIdle:
            truckMarker(color: .orange)
        case .truckStopped:
            truckMarker(color: .red)
        }
    }

    private func truckMarker(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: "truck.box.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
        }
    }

    private func fitToRoute() {
        var coords = annotations.map(\.coordinate)
        if !routeCoordinates.isEmpty {
            coords.append(contentsOf: routeCoordinates.map {
                CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
            })
        }
        guard !coords.isEmpty else { return }

        let region = MKCoordinateRegion(coordinates: coords)
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
    }
}

// MARK: - MKCoordinateRegion from coordinates

extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 38.5, longitude: -82.0),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
            return
        }

        let minLat = coordinates.map(\.latitude).min()!
        let maxLat = coordinates.map(\.latitude).max()!
        let minLon = coordinates.map(\.longitude).min()!
        let maxLon = coordinates.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.3)
        )
        self = MKCoordinateRegion(center: center, span: span)
    }
}
