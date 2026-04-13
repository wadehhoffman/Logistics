import Foundation
import CoreLocation

/// Routing client that talks to our server-side proxy.
///
/// The server handles the fallback chain (Mapbox driving-traffic → Mapbox
/// driving → OSRM → Haversine) so this actor just makes one request and
/// parses the Mapbox-shaped response. When `useTruckProfile` is true we hit
/// `/api/truck-route` which uses OpenRouteService HGV (when ORS_API_KEY is
/// configured on the server) or falls back to Mapbox driving if not.
///
/// Kept the original class name `MapboxRoutingService` so existing call sites
/// don't need updates; the meaning has shifted from "direct Mapbox" to
/// "our routing proxy (which uses Mapbox under the hood)".
actor MapboxRoutingService {
    private let baseURL: String
    private let session: URLSession

    /// Back-compat initializer (kept so older code paths that passed a
    /// Mapbox token continue to compile). Token is ignored — routing runs
    /// server-side now.
    init(mapboxToken: String = "", baseURL: String = "http://logistics-ai.carterlumber.com") {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Calculate a route between waypoints. Server handles the fallback chain.
    /// - Parameter useTruckProfile: when true, uses /api/truck-route (HGV-aware)
    ///   which respects truck road restrictions via OpenRouteService.
    func calculateRoute(
        waypoints: [CLLocationCoordinate2D],
        useTruckProfile: Bool = false
    ) async throws -> RouteResult {
        guard waypoints.count >= 2 else {
            throw RoutingError.insufficientWaypoints
        }

        let coordString = waypoints
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let path = useTruckProfile ? "/api/truck-route" : "/api/route"
        let urlStr = "\(baseURL)\(path)?coords=\(coordString)&overview=full"

        guard let url = URL(string: urlStr) else { throw RoutingError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("CarterLumberRouteApp/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RoutingError.networkError("Invalid response")
            }
            guard http.statusCode == 200 else {
                // Server already reports 504/502 for its own fallback failures;
                // drop back to Haversine so the UI still has something to show.
                return Haversine.fallbackRoute(from: waypoints.first!, to: waypoints.last!)
            }
            return try parseRouteResponse(data)
        } catch let error as RoutingError {
            throw error
        } catch {
            // Network failure → same graceful fallback
            return Haversine.fallbackRoute(from: waypoints.first!, to: waypoints.last!)
        }
    }

    /// Calculate a multi-waypoint route and split into legs (used by Today
    /// dashboard for truck → mill → yard routing).
    func calculateRouteWithLegs(
        waypoints: [CLLocationCoordinate2D],
        legNames: [(from: String, to: String)],
        useTruckProfile: Bool = false
    ) async throws -> (legs: [RouteLeg], combinedGeometry: RouteGeometry?) {
        guard waypoints.count >= 2, legNames.count == waypoints.count - 1 else {
            throw RoutingError.insufficientWaypoints
        }

        let result = try await calculateRoute(waypoints: waypoints, useTruckProfile: useTruckProfile)

        // For 3-waypoint (truck → mill → yard) routes, approximate leg split
        // by finding the coordinate closest to the middle waypoint.
        if waypoints.count == 3, let geometry = result.geometry {
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

        let leg = RouteLeg(
            from: legNames[0].from, to: legNames.last!.to,
            distance: result.distance, duration: result.duration,
            geometry: result.geometry
        )
        return ([leg], result.geometry)
    }

    // MARK: - Response parsing

    /// Server returns a Mapbox-compatible shape whether the underlying engine
    /// was Mapbox, OSRM, ORS HGV, or the haversine fallback.
    /// `_fallback: true` (optional) flags the haversine estimate.
    private func parseRouteResponse(_ data: Data) throws -> RouteResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? String, code == "Ok",
              let routes = json["routes"] as? [[String: Any]],
              let route = routes.first else {
            throw RoutingError.parseError
        }

        let distance = route["distance"] as? Double ?? 0
        let duration = route["duration"] as? Double ?? 0
        let isFallback = (json["_fallback"] as? Bool) ?? false
        let note = json["_note"] as? String

        var geometry: RouteGeometry?
        if let geoJson = route["geometry"] as? [String: Any],
           let coords = geoJson["coordinates"] as? [[Double]] {
            geometry = RouteGeometry(coordinates: coords)
        }

        return RouteResult(
            distance: distance,
            duration: duration,
            geometry: geometry,
            isFallback: isFallback,
            fallbackNote: note
        )
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
            case .invalidURL:            return "Invalid routing URL"
            case .rateLimited:           return "API rate limited"
            case .networkError(let m):   return "Network error: \(m)"
            case .parseError:            return "Failed to parse route response"
            }
        }
    }
}
