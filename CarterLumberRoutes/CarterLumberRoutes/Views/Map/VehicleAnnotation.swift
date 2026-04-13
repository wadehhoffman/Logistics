import Foundation
import MapKit

/// Wraps a Vehicle in a reference-typed MKAnnotation so MapKit can cluster
/// overlapping markers. Using a common clusteringIdentifier means trucks
/// and trailers in the same spot collapse into a single count bubble.
final class VehicleAnnotation: NSObject, MKAnnotation {
    let vehicle: Vehicle
    let coordinate: CLLocationCoordinate2D
    var title: String? { vehicle.operatorOrDriver.isEmpty ? vehicle.name : "\(vehicle.name) – \(vehicle.operatorOrDriver)" }
    var subtitle: String? {
        let loc = [vehicle.city, vehicle.state].filter { !$0.isEmpty }.joined(separator: ", ")
        return loc.isEmpty ? nil : loc
    }

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        self.coordinate = vehicle.coordinate
        super.init()
    }
}

/// Mill / Yard endpoint pin for route polylines. Not clustered — routes
/// typically don't overlap enough for it to matter, and users want to see
/// every mill/yard on a route.
final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    enum Kind { case mill, yard }
    let kind: Kind
    let coordinate: CLLocationCoordinate2D
    var title: String?
    var subtitle: String?

    init(kind: Kind, coordinate: CLLocationCoordinate2D, title: String?, subtitle: String? = nil) {
        self.kind = kind
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        super.init()
    }
}

/// Color-coded polyline overlay that carries its own status color so the
/// map renderer can pick the right stroke without cross-referencing.
final class StatusPolyline: MKPolyline {
    var strokeColor: UIColor = .systemBlue
    var isCancelled: Bool = false
}
