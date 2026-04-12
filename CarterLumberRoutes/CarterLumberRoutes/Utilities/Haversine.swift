import Foundation
import CoreLocation

enum Haversine {
    /// Calculate the great-circle distance between two points in kilometers.
    static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0 // Earth radius in km
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Calculate distance between two CLLocationCoordinate2D in kilometers.
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        distance(lat1: from.latitude, lon1: from.longitude, lat2: to.latitude, lon2: to.longitude)
    }

    /// Generate a fallback route estimate using straight-line distance × road factor.
    static func fallbackRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        roadFactor: Double = 1.32,
        avgSpeedKmh: Double = 80
    ) -> RouteResult {
        let straightKm = distance(from: from, to: to)
        let roadKm = straightKm * roadFactor
        let distanceMeters = roadKm * 1000
        let durationSeconds = (roadKm / avgSpeedKmh) * 3600

        // Generate simple interpolated geometry
        let steps = 20
        var coordinates: [[Double]] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let lat = from.latitude + (to.latitude - from.latitude) * t
            let lon = from.longitude + (to.longitude - from.longitude) * t
            coordinates.append([lon, lat])
        }

        return RouteResult(
            distance: distanceMeters,
            duration: durationSeconds,
            geometry: RouteGeometry(coordinates: coordinates),
            isFallback: true,
            fallbackNote: "Estimated via straight-line distance ×\(roadFactor) road factor"
        )
    }
}
