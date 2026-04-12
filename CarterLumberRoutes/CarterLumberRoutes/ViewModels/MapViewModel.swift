import Foundation
import CoreLocation
import SwiftUI

@MainActor @Observable
final class MapViewModel {
    var routeCoordinates: [[Double]] = []
    var millAnnotation: MapAnnotation?
    var yardAnnotation: MapAnnotation?
    var truckAnnotation: MapAnnotation?
    var vehicleAnnotations: [MapAnnotation] = []
    var showTrafficLayer = false
    var showTruckLayer = false
    var shouldFitBounds = false
    var isFallbackRoute = false

    struct MapAnnotation: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let title: String
        let subtitle: String
        let type: AnnotationType

        enum AnnotationType {
            case mill
            case yard
            case truckMoving
            case truckIdle
            case truckStopped
        }
    }

    var allAnnotations: [MapAnnotation] {
        var all: [MapAnnotation] = []
        if let mill = millAnnotation { all.append(mill) }
        if let yard = yardAnnotation { all.append(yard) }
        if let truck = truckAnnotation { all.append(truck) }
        if showTruckLayer { all.append(contentsOf: vehicleAnnotations) }
        return all
    }

    var boundsCoordinates: [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        if let mill = millAnnotation { coords.append(mill.coordinate) }
        if let yard = yardAnnotation { coords.append(yard.coordinate) }
        if let truck = truckAnnotation { coords.append(truck.coordinate) }
        return coords
    }

    func setRoute(result: RouteResult, mill: Mill, millCoord: CLLocationCoordinate2D, yard: Yard) {
        routeCoordinates = result.geometry?.coordinates ?? []
        isFallbackRoute = result.isFallback

        millAnnotation = MapAnnotation(
            coordinate: millCoord,
            title: mill.name,
            subtitle: "\(mill.city), \(mill.state)",
            type: .mill
        )
        yardAnnotation = MapAnnotation(
            coordinate: yard.coordinate,
            title: "#\(yard.posNumber)",
            subtitle: "\(yard.city), \(yard.state)",
            type: .yard
        )
        truckAnnotation = nil
        shouldFitBounds = true
    }

    func setTruckRoute(geometry: RouteGeometry?, vehicle: Vehicle, mill: Mill, millCoord: CLLocationCoordinate2D, yard: Yard) {
        routeCoordinates = geometry?.coordinates ?? []
        isFallbackRoute = false

        truckAnnotation = MapAnnotation(
            coordinate: vehicle.coordinate,
            title: vehicle.name,
            subtitle: vehicle.status.label,
            type: vehicle.status == .moving ? .truckMoving :
                  vehicle.status == .idle ? .truckIdle : .truckStopped
        )
        millAnnotation = MapAnnotation(
            coordinate: millCoord,
            title: mill.name,
            subtitle: "\(mill.city), \(mill.state)",
            type: .mill
        )
        yardAnnotation = MapAnnotation(
            coordinate: yard.coordinate,
            title: "#\(yard.posNumber)",
            subtitle: "\(yard.city), \(yard.state)",
            type: .yard
        )
        shouldFitBounds = true
    }

    func updateVehicles(_ vehicles: [Vehicle]) {
        vehicleAnnotations = vehicles.map { v in
            MapAnnotation(
                coordinate: v.coordinate,
                title: v.name,
                subtitle: "\(v.status.label) — \(v.driver.isEmpty ? "No driver" : v.driver)",
                type: v.status == .moving ? .truckMoving :
                      v.status == .idle ? .truckIdle : .truckStopped
            )
        }
    }

    func clearRoute() {
        routeCoordinates = []
        millAnnotation = nil
        yardAnnotation = nil
        truckAnnotation = nil
        isFallbackRoute = false
    }
}
