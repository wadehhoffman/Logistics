import Foundation
import CoreLocation

actor GeocodingService {
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    /// Geocode an address to coordinates using Nominatim.
    /// Falls back to a shorter address (everything after first comma) if full address fails.
    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        // Check cache first
        if let cached = cache[address] {
            return cached
        }

        // Try full address
        if let coord = try? await nominatimSearch(query: address) {
            cache[address] = coord
            return coord
        }

        // Fallback: try without street (everything after first comma)
        if let commaIdx = address.firstIndex(of: ",") {
            let shorter = String(address[address.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            if let coord = try? await nominatimSearch(query: shorter) {
                cache[address] = coord
                return coord
            }
        }

        throw GeocodingError.notFound(address)
    }

    private func nominatimSearch(query: String) async throws -> CLLocationCoordinate2D? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=\(encoded)") else {
            throw GeocodingError.invalidAddress
        }

        var request = URLRequest(url: url)
        request.setValue("CarterLumberRouteApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeocodingError.networkError
        }

        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = results.first,
              let latStr = first["lat"] as? String,
              let lonStr = first["lon"] as? String,
              let lat = Double(latStr),
              let lon = Double(lonStr) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    enum GeocodingError: Error, LocalizedError {
        case invalidAddress
        case networkError
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .invalidAddress: return "Invalid address"
            case .networkError: return "Geocoding service unavailable"
            case .notFound(let addr): return "Could not geocode: \(addr)"
            }
        }
    }
}
