import Foundation

actor IntelliShiftService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    /// Fetch vehicle locations from the Node.js proxy server.
    /// The server handles IntelliShift authentication and Branch 570 filtering.
    func fetchVehicles() async throws -> [Vehicle] {
        guard let url = URL(string: "\(baseURL)/api/intellishift/vehicles") else {
            throw IntelliShiftError.invalidURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntelliShiftError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 503 {
            throw IntelliShiftError.notConfigured
        }

        guard httpResponse.statusCode == 200 else {
            throw IntelliShiftError.networkError("Status \(httpResponse.statusCode)")
        }

        let vehiclesResponse = try JSONDecoder().decode(VehiclesResponse.self, from: data)
        return vehiclesResponse.vehicles
    }

    enum IntelliShiftError: Error, LocalizedError {
        case invalidURL
        case notConfigured
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid IntelliShift proxy URL"
            case .notConfigured: return "IntelliShift credentials not configured on server"
            case .networkError(let msg): return "IntelliShift error: \(msg)"
            }
        }
    }
}
