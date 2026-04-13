import Foundation
import CoreLocation

/// Geocoding client that routes through our server's /api/geocode proxy
/// (which itself calls Nominatim, so no changes to caching/fallback semantics).
/// Keeps the original public API unchanged so call sites don't need updates.
actor GeocodingService {
    private let baseURL: String
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private let session: URLSession

    init(baseURL: String = "http://logistics-ai.carterlumber.com") {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    /// Geocode an address to coordinates via /api/geocode.
    /// Falls back to the address after the first comma if the full query fails.
    func geocode(address: String) async throws -> CLLocationCoordinate2D {
        if let cached = cache[address] { return cached }

        if let coord = try? await proxySearch(query: address) {
            cache[address] = coord
            return coord
        }

        if let commaIdx = address.firstIndex(of: ",") {
            let shorter = String(address[address.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
            if let coord = try? await proxySearch(query: shorter) {
                cache[address] = coord
                return coord
            }
        }

        throw GeocodingError.notFound(address)
    }

    private func proxySearch(query: String) async throws -> CLLocationCoordinate2D? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/geocode?q=\(encoded)") else {
            throw GeocodingError.invalidAddress
        }

        var request = URLRequest(url: url)
        request.setValue("CarterLumberRouteApp/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeocodingError.networkError
        }

        // Server proxies the raw Nominatim response: an array of result objects
        // with string lat/lon fields. Same shape as before.
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
            case .invalidAddress:        return "Invalid address"
            case .networkError:          return "Geocoding service unavailable"
            case .notFound(let addr):    return "Could not geocode: \(addr)"
            }
        }
    }
}
