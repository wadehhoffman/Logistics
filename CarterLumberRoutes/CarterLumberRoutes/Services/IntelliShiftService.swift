import Foundation

actor IntelliShiftService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
        print("[IntelliShift] Initialized with baseURL: \(self.baseURL)")
    }

    func fetchVehicles() async throws -> [Vehicle] {
        let urlString = "\(baseURL)/api/intellishift/vehicles"
        print("[IntelliShift] Fetching vehicles from: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("[IntelliShift] ERROR: Invalid URL")
            throw IntelliShiftError.invalidURL
        }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[IntelliShift] ERROR: Invalid response type")
                throw IntelliShiftError.networkError("Invalid response")
            }

            print("[IntelliShift] Response status: \(httpResponse.statusCode), bytes: \(data.count)")

            if httpResponse.statusCode == 503 {
                throw IntelliShiftError.notConfigured
            }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "n/a"
                print("[IntelliShift] ERROR body: \(body.prefix(200))")
                throw IntelliShiftError.networkError("Status \(httpResponse.statusCode)")
            }

            let vehiclesResponse = try JSONDecoder().decode(VehiclesResponse.self, from: data)
            print("[IntelliShift] Decoded \(vehiclesResponse.vehicles.count) vehicles")
            return vehiclesResponse.vehicles
        } catch let error as IntelliShiftError {
            throw error
        } catch {
            print("[IntelliShift] NETWORK ERROR: \(error.localizedDescription)")
            throw IntelliShiftError.networkError(error.localizedDescription)
        }
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
