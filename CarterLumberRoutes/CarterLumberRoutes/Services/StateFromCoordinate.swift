import Foundation
import CoreLocation

enum StateFromCoordinate {
    struct StateBounds {
        let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    }

    static let stateBounds: [String: StateBounds] = [
        "AL": StateBounds(minLat: 30.22, maxLat: 35.01, minLon: -88.47, maxLon: -84.89),
        "AR": StateBounds(minLat: 33.00, maxLat: 36.50, minLon: -94.42, maxLon: -89.65),
        "CT": StateBounds(minLat: 40.98, maxLat: 42.05, minLon: -73.73, maxLon: -71.80),
        "DE": StateBounds(minLat: 38.45, maxLat: 39.84, minLon: -75.79, maxLon: -75.05),
        "FL": StateBounds(minLat: 24.54, maxLat: 30.99, minLon: -87.63, maxLon: -80.03),
        "GA": StateBounds(minLat: 30.36, maxLat: 35.00, minLon: -85.61, maxLon: -80.84),
        "IL": StateBounds(minLat: 37.00, maxLat: 42.51, minLon: -91.51, maxLon: -87.02),
        "IN": StateBounds(minLat: 37.78, maxLat: 41.76, minLon: -88.10, maxLon: -84.80),
        "IA": StateBounds(minLat: 40.38, maxLat: 43.50, minLon: -96.64, maxLon: -90.14),
        "KS": StateBounds(minLat: 37.00, maxLat: 40.00, minLon: -102.05, maxLon: -94.59),
        "KY": StateBounds(minLat: 36.50, maxLat: 39.14, minLon: -89.57, maxLon: -81.96),
        "LA": StateBounds(minLat: 29.00, maxLat: 33.02, minLon: -94.05, maxLon: -88.82),
        "ME": StateBounds(minLat: 43.05, maxLat: 47.46, minLon: -71.09, maxLon: -66.95),
        "MD": StateBounds(minLat: 37.91, maxLat: 39.72, minLon: -79.49, maxLon: -75.05),
        "MA": StateBounds(minLat: 41.24, maxLat: 42.89, minLon: -73.51, maxLon: -69.93),
        "MI": StateBounds(minLat: 41.70, maxLat: 48.26, minLon: -90.42, maxLon: -82.12),
        "MN": StateBounds(minLat: 43.50, maxLat: 49.38, minLon: -97.24, maxLon: -89.49),
        "MS": StateBounds(minLat: 30.17, maxLat: 35.00, minLon: -91.66, maxLon: -88.10),
        "MO": StateBounds(minLat: 36.00, maxLat: 40.61, minLon: -95.77, maxLon: -89.10),
        "NC": StateBounds(minLat: 33.84, maxLat: 36.59, minLon: -84.32, maxLon: -75.46),
        "NH": StateBounds(minLat: 42.70, maxLat: 45.31, minLon: -72.56, maxLon: -70.70),
        "NJ": StateBounds(minLat: 38.93, maxLat: 41.36, minLon: -75.56, maxLon: -73.89),
        "NY": StateBounds(minLat: 40.50, maxLat: 45.02, minLon: -79.76, maxLon: -71.86),
        "OH": StateBounds(minLat: 38.40, maxLat: 41.98, minLon: -84.82, maxLon: -80.52),
        "OK": StateBounds(minLat: 33.62, maxLat: 37.00, minLon: -103.00, maxLon: -94.43),
        "PA": StateBounds(minLat: 39.72, maxLat: 42.27, minLon: -80.52, maxLon: -74.69),
        "RI": StateBounds(minLat: 41.15, maxLat: 42.02, minLon: -71.86, maxLon: -71.12),
        "SC": StateBounds(minLat: 32.03, maxLat: 35.21, minLon: -83.35, maxLon: -78.54),
        "TN": StateBounds(minLat: 34.98, maxLat: 36.68, minLon: -90.31, maxLon: -81.65),
        "TX": StateBounds(minLat: 25.84, maxLat: 36.50, minLon: -106.65, maxLon: -93.51),
        "VT": StateBounds(minLat: 42.73, maxLat: 45.02, minLon: -73.44, maxLon: -71.47),
        "VA": StateBounds(minLat: 36.54, maxLat: 39.47, minLon: -83.68, maxLon: -75.24),
        "WV": StateBounds(minLat: 37.20, maxLat: 40.64, minLon: -82.64, maxLon: -77.72),
        "WI": StateBounds(minLat: 42.49, maxLat: 47.08, minLon: -92.89, maxLon: -86.25),
        "DC": StateBounds(minLat: 38.79, maxLat: 38.99, minLon: -77.12, maxLon: -76.91),
        "CO": StateBounds(minLat: 37.00, maxLat: 41.00, minLon: -109.06, maxLon: -102.04),
        "NM": StateBounds(minLat: 31.33, maxLat: 37.00, minLon: -109.05, maxLon: -103.00),
        "AZ": StateBounds(minLat: 31.33, maxLat: 37.00, minLon: -114.82, maxLon: -109.04),
        "NV": StateBounds(minLat: 35.00, maxLat: 42.00, minLon: -120.01, maxLon: -114.04),
        "UT": StateBounds(minLat: 37.00, maxLat: 42.00, minLon: -114.05, maxLon: -109.04),
        "WY": StateBounds(minLat: 41.00, maxLat: 45.00, minLon: -111.06, maxLon: -104.05),
    ]

    /// Look up a state code from lat/lon using bounding boxes.
    static func getState(lat: Double, lon: Double) -> String? {
        var candidates: [(state: String, distance: Double)] = []
        for (state, bounds) in stateBounds {
            if lat >= bounds.minLat && lat <= bounds.maxLat &&
               lon >= bounds.minLon && lon <= bounds.maxLon {
                let centerLat = (bounds.minLat + bounds.maxLat) / 2
                let centerLon = (bounds.minLon + bounds.maxLon) / 2
                let distance = sqrt(pow(lat - centerLat, 2) + pow(lon - centerLon, 2))
                candidates.append((state, distance))
            }
        }
        return candidates.min(by: { $0.distance < $1.distance })?.state
    }

    /// Walk a route geometry and determine miles in each state.
    static func getStatesFromRoute(
        coordinates: [[Double]],
        originState: String?,
        destState: String?,
        totalDistanceMiles: Double
    ) -> [StateMileage] {
        guard coordinates.count >= 2 else {
            // Can't determine states, split evenly between origin and dest
            let o = originState ?? "??"
            let d = destState ?? "??"
            if o == d {
                return [StateMileage(state: o, miles: totalDistanceMiles, fraction: 1.0)]
            }
            return [
                StateMileage(state: o, miles: totalDistanceMiles * 0.5, fraction: 0.5),
                StateMileage(state: d, miles: totalDistanceMiles * 0.5, fraction: 0.5),
            ]
        }

        // Sample every Nth point
        let step = max(1, coordinates.count / 50)
        var segments: [(state: String, startIdx: Int)] = []
        var prevState: String?

        for i in stride(from: 0, to: coordinates.count, by: step) {
            let lon = coordinates[i][0]
            let lat = coordinates[i][1]
            let st = getState(lat: lat, lon: lon) ?? prevState
            if let st = st, st != prevState {
                segments.append((st, i))
                prevState = st
            } else if prevState == nil, let st = st {
                segments.append((st, i))
                prevState = st
            }
        }

        // Check last point
        if let last = coordinates.last {
            let lastState = getState(lat: last[1], lon: last[0])
            if let ls = lastState, ls != prevState {
                segments.append((ls, coordinates.count - 1))
            }
        }

        guard !segments.isEmpty else {
            let o = originState ?? "??"
            let d = destState ?? "??"
            return [
                StateMileage(state: o, miles: totalDistanceMiles * 0.5, fraction: 0.5),
                StateMileage(state: d, miles: totalDistanceMiles * 0.5, fraction: 0.5),
            ]
        }

        // Calculate distance in each state segment
        var stateKm: [String: Double] = [:]
        for s in 0..<segments.count {
            let startI = segments[s].startIdx
            let endI = s < segments.count - 1 ? segments[s + 1].startIdx : coordinates.count - 1
            var dist = 0.0
            for i in startI..<endI {
                dist += Haversine.distance(
                    lat1: coordinates[i][1], lon1: coordinates[i][0],
                    lat2: coordinates[i + 1][1], lon2: coordinates[i + 1][0]
                )
            }
            stateKm[segments[s].state, default: 0] += dist
        }

        let totalKm = stateKm.values.reduce(0, +)
        guard totalKm > 0 else {
            return segments.map {
                StateMileage(state: $0.state, miles: totalDistanceMiles / Double(segments.count), fraction: 1.0 / Double(segments.count))
            }
        }

        return stateKm.map { state, km in
            StateMileage(
                state: state,
                miles: (km / totalKm) * totalDistanceMiles,
                fraction: km / totalKm
            )
        }.sorted { $0.miles > $1.miles }
    }
}
