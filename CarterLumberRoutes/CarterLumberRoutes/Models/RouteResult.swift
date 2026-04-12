import Foundation
import CoreLocation

struct RouteResult {
    let distance: Double        // meters
    let duration: Double        // seconds
    let geometry: RouteGeometry?
    let isFallback: Bool
    let fallbackNote: String?

    var distanceMiles: Double { distance / 1609.344 }
    var distanceKm: Double { distance / 1000.0 }

    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }

    var formattedDuration: String {
        FormatHelpers.formatDuration(duration)
    }
}

struct RouteGeometry {
    let coordinates: [[Double]]  // [lon, lat] pairs

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }
}

struct RouteLeg {
    let from: String
    let to: String
    let distance: Double         // meters
    let duration: Double         // seconds
    let geometry: RouteGeometry?

    var distanceMiles: Double { distance / 1609.344 }

    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }

    var formattedDuration: String {
        FormatHelpers.formatDuration(duration)
    }
}

struct TwoLegRoute {
    let leg1: RouteLeg           // truck → mill
    let leg2: RouteLeg           // mill → yard
    let combinedGeometry: RouteGeometry?

    var totalDistance: Double { leg1.distance + leg2.distance }
    var totalDuration: Double { leg1.duration + leg2.duration }
    var totalDistanceMiles: Double { totalDistance / 1609.344 }

    var formattedTotalDistance: String {
        String(format: "%.1f mi", totalDistanceMiles)
    }

    var formattedTotalDuration: String {
        FormatHelpers.formatDuration(totalDuration)
    }
}
