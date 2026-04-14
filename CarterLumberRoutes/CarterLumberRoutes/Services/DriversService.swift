import Foundation

/// Fetches enriched driver data from our server's /api/drivers endpoint,
/// which aggregates IntelliShift operators + shift assignments + schedule
/// cross-reference + HOS calculations server-side.
actor DriversService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30  // server aggregates multiple IS calls
        self.session = URLSession(configuration: config)
    }

    func fetchDrivers() async throws -> DriversResponse {
        guard let url = URL(string: "\(baseURL)/api/drivers") else {
            throw DriversError.invalidURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else {
            throw DriversError.networkError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DriversError.networkError("Status \(http.statusCode): \(body.prefix(200))")
        }

        return try JSONDecoder().decode(DriversResponse.self, from: data)
    }

    enum DriversError: Error, LocalizedError {
        case invalidURL
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:          return "Invalid server URL"
            case .networkError(let m): return "Drivers error: \(m)"
            }
        }
    }
}
