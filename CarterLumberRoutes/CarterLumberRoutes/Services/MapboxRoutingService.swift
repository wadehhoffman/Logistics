import Foundation
import CoreLocation

actor MapboxRoutingService {
    private let mapboxToken: String
    private let session: URLSession

    init(mapboxToken: String) {
        self.mapboxToken = mapboxToken
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    /// Calculate a route between waypoints with automatic fallback chain.
    /// Mapbox driving-traffic → Mapbox driving → OSRM → Haversine estimate
    func calculateRoute(waypoints: [CLLocationCoordinate2D]) async throws -> RouteResult {
        guard waypoints.count >= 2 else {
            throw RoutingError.insufficientWaypoints
        }

        let coordString = waypoints.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")

        // Try 1: Mapbox driving-traffic (real-time congestion)
        if let result = try? await fetchMapboxRoute(coords: coordString, profile: "driving-traffic") {
            return result
        }

        // Try 2: Mapbox driving (no traffic)
        if let result = try? await fetchMapboxRoute(coords: coordString, profile: "driving") {
            return result
        }

        // Try 3: OSRM (free, open-source)
        if let result = try? await fetchOSRMRoute(coords: coordString) {
            return result
        }

        // Try 4: Haversine fallback
        return Haversine.fallbackRoute(from: waypoints.first!, to: waypoints.last!)
    }

    /// Calculate a route and return separate legs (for truck routing).
    func calculateRouteWithLegs(
        waypoints: [CLLocationCoordinate2D],
        legNames: [(from: String, to: String)]
    ) async throws -> (legs: [RouteLeg], combinedGeometry: RouteGeometry?) {
        guard waypoints.count >= 2, legNames.count == waypoints.count - 1 else {
            throw RoutingError.insufficientWaypoints
        }

        // Calculate full route through all waypoints
        let result = try await calculateRoute(waypoints: waypoints)

        // If we got geometry, split it into legs
        if waypoints.count == 3, let geometry = result.geometry {
            // For 3-waypoint routes (truck → mill → yard), approximate leg split
            // by finding the coordinate closest to the middle waypoint
            let midWaypoint = waypoints[1]
            var bestIdx = 0
            var bestDist = Double.infinity
            for (i, coord) in geometry.coordinates.enumerated() {
                let d = Haversine.distance(
                    lat1: coord[1], lon1: coord[0],
                    lat2: midWaypoint.latitude, lon2: midWaypoint.longitude
                )
                if d < bestDist {
                    bestDist = d
                    bestIdx = i
                }
            }

            let leg1Coords = Array(geometry.coordinates[0...bestIdx])
            let leg2Coords = Array(geometry.coordinates[bestIdx...])

            // Calculate distances for each leg
            let leg1Dist = calculateGeometryDistance(leg1Coords)
            let leg2Dist = calculateGeometryDistance(leg2Coords)
            let totalDist = leg1Dist + leg2Dist

            let leg1Duration = totalDist > 0 ? result.duration * (leg1Dist / totalDist) : result.duration / 2
            let leg2Duration = totalDist > 0 ? result.duration * (leg2Dist / totalDist) : result.duration / 2

            let legs = [
                RouteLeg(
                    from: legNames[0].from, to: legNames[0].to,
                    distance: leg1Dist * 1000, duration: leg1Duration,
                    geometry: RouteGeometry(coordinates: leg1Coords)
                ),
                RouteLeg(
                    from: legNames[1].from, to: legNames[1].to,
                    distance: leg2Dist * 1000, duration: leg2Duration,
                    geometry: RouteGeometry(coordinates: leg2Coords)
                ),
            ]
            return (legs, geometry)
        }

        // Fallback: single leg
        let leg = RouteLeg(
            from: legNames[0].from, to: legNames.last!.to,
            distance: result.distance, duration: result.duration,
            geometry: result.geometry
        )
        return ([leg], result.geometry)
    }

    // MARK: - Mapbox API

    private func fetchMapboxRoute(coords: String, profile: String) async throws -> RouteResult {
        let urlStr = "https://api.mapbox.com/directions/v5/mapbox/\(profile)/\(coords)" +
            "?geometries=geojson&overview=full&annotations=duration,distance&access_token=\(mapboxToken)"
        guard let url = URL(string: urlStr) else { throw RoutingError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("CarterLumberRouteApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoutingError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 429 || httpResponse.statusCode == 403 {
            throw RoutingError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw RoutingError.networkError("Status \(httpResponse.statusCode)")
        }

        return try parseMapboxResponse(data)
    }

    private func parseMapboxResponse(_ data: Data) throws -> RouteResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "Ok",
              let routes = json["routes"] as? [[String: Any]],
              let route = routes.first else {
            throw RoutingError.parseError
        }

        let distance = route["distance"] as? Double ?? 0
        let duration = route["duration"] as? Double ?? 0

        var geometry: RouteGeometry?
        if let geoJson = route["geometry"] as? [String: Any],
           let coords = geoJson["coordinates"] as? [[Double]] {
            geometry = RouteGeometry(coordinates: coords)
        }

        return RouteResult(
            distance: distance,
            duration: duration,
            geometry: geometry,
            isFallback: false,
            fallbackNote: nil
        )
    }

    // MARK: - OSRM API

    private func fetchOSRMRoute(coords: String) async throws -> RouteResult {
        let urlStr = "https://router.project-osrm.org/route/v1/driving/\(coords)?overview=full&geometries=geojson"
        guard let url = URL(string: urlStr) else { throw RoutingError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("CarterLumberRouteApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RoutingError.networkError("OSRM unavailable")
        }

        return try parseMapboxResponse(data) // OSRM uses same response format
    }

    // MARK: - Helpers

    private func calculateGeometryDistance(_ coordinates: [[Double]]) -> Double {
        var total = 0.0
        for i in 0..<coordinates.count - 1 {
            total += Haversine.distance(
                lat1: coordinates[i][1], lon1: coordinates[i][0],
                lat2: coordinates[i + 1][1], lon2: coordinates[i + 1][0]
            )
        }
        return total
    }

    enum RoutingError: Error, LocalizedError {
        case insufficientWaypoints
        case invalidURL
        case rateLimited
        case networkError(String)
        case parseError

        var errorDescription: String? {
            switch self {
            case .insufficientWaypoints: return "At least 2 waypoints required"
            case .invalidURL: return "Invalid routing URL"
            case .rateLimited: return "API rate limited"
            case .networkError(let msg): return "Network error: \(msg)"
            case .parseError: return "Failed to parse route response"
            }
        }
    }
}
