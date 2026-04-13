import Foundation

/// Server-backed reference data fetcher.
///
/// Mirrors the IntelliShiftService pattern: actor-isolated, custom error enum,
/// 20-second URLSession timeout. Calls our Node.js backend at /api/mills and
/// /api/yards which return the canonical Mill / Yard JSON shapes that the iOS
/// models (post-Phase iA) decode directly.
///
/// Phase iB only uses the read endpoints. Phase iF will extend this service
/// with create/update/delete plus geocode-all and the activity log.
actor MillsYardsService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    func fetchMills() async throws -> [Mill] {
        try await fetch(path: "/api/mills", key: "mills")
    }

    func fetchYards() async throws -> [Yard] {
        try await fetch(path: "/api/yards", key: "yards")
    }

    /// Generic fetch + decode. Server response shape is `{ "<key>": [...], "total": N }`.
    /// We decode with a one-off wrapper struct to avoid two near-identical blocks.
    private func fetch<T: Decodable>(path: String, key: String) async throws -> [T] {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MillsYardsError.invalidURL }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else {
                throw MillsYardsError.networkError("Invalid response")
            }
            guard http.statusCode == 200 else {
                throw MillsYardsError.networkError("Status \(http.statusCode)")
            }

            // Decode into a dynamic dictionary so the same code handles mills and yards.
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let arr = json?[key] else {
                throw MillsYardsError.decodingError("Missing '\(key)' key in response")
            }
            let arrData = try JSONSerialization.data(withJSONObject: arr)
            return try JSONDecoder().decode([T].self, from: arrData)
        } catch let e as MillsYardsError {
            throw e
        } catch {
            throw MillsYardsError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Mills CRUD (Phase iF)

    struct CreateMillPayload: Codable {
        let name: String
        let product: String
        let vendor: String
        let street: String
        let city: String
        let stateZip: String
        let address: String
    }

    /// Create a mill. Server auto-geocodes the address and returns the full
    /// Mill object including uuid, lat, lon.
    func createMill(_ payload: CreateMillPayload) async throws -> Mill {
        try await mutate(method: "POST", path: "/api/mills", body: payload, responseKey: "mill")
    }

    /// Update an existing mill. If address changes server re-geocodes automatically.
    func updateMill(uuid: String, payload: CreateMillPayload) async throws -> Mill {
        try await mutate(method: "PUT", path: "/api/mills/\(uuid)", body: payload, responseKey: "mill")
    }

    func deleteMill(uuid: String) async throws {
        try await delete(path: "/api/mills/\(uuid)")
    }

    /// Kick off the server's bulk geocode backfill. Rate-limited to ~1 req/sec
    /// per mill, so this can take 60+ seconds for a full refresh.
    func geocodeAllMills() async throws -> GeocodeAllResult {
        guard let url = URL(string: "\(baseURL)/api/mills/geocode-all") else { throw MillsYardsError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // Long timeout — server iterates all mills at ~1 req/sec.
        var longConfig = URLSessionConfiguration.default
        longConfig.timeoutIntervalForRequest = 300
        let longSession = URLSession(configuration: longConfig)
        let (data, response) = try await longSession.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MillsYardsError.networkError("Geocode-all failed")
        }
        return try JSONDecoder().decode(GeocodeAllResult.self, from: data)
    }

    struct GeocodeAllResult: Codable {
        let total: Int
        let succeeded: Int
        let failed: Int
        let failures: [Failure]

        struct Failure: Codable {
            let name: String
            let address: String
        }
    }

    // MARK: - Yards CRUD (Phase iF)

    struct CreateYardPayload: Codable {
        let storeNumber: String
        let posNumber: String
        let storeType: String
        let street: String
        let city: String
        let state: String
        let zip: String
        let lat: Double?
        let lon: Double?
        let manager: String
        let market: String
    }

    func createYard(_ payload: CreateYardPayload) async throws -> Yard {
        try await mutate(method: "POST", path: "/api/yards", body: payload, responseKey: "yard")
    }

    func updateYard(uuid: String, payload: CreateYardPayload) async throws -> Yard {
        try await mutate(method: "PUT", path: "/api/yards/\(uuid)", body: payload, responseKey: "yard")
    }

    func deleteYard(uuid: String) async throws {
        try await delete(path: "/api/yards/\(uuid)")
    }

    // MARK: - Activity log (Phase iF)

    func fetchActivity(limit: Int = 100, offset: Int = 0) async throws -> ActivityListResponse {
        guard let url = URL(string: "\(baseURL)/api/activity?limit=\(limit)&offset=\(offset)") else {
            throw MillsYardsError.invalidURL
        }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MillsYardsError.networkError("Activity fetch failed")
        }
        return try JSONDecoder().decode(ActivityListResponse.self, from: data)
    }

    // MARK: - Private mutation helpers

    /// Generic POST/PUT that wraps a `{ "<responseKey>": {...} }` reply.
    private func mutate<Body: Encodable, Output: Decodable>(
        method: String,
        path: String,
        body: Body,
        responseKey: String
    ) async throws -> Output {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MillsYardsError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw MillsYardsError.networkError("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MillsYardsError.networkError("Status \(http.statusCode): \(body.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let obj = json[responseKey] else {
            throw MillsYardsError.decodingError("Missing '\(responseKey)' in response")
        }
        let objData = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(Output.self, from: objData)
    }

    private func delete(path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw MillsYardsError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MillsYardsError.networkError("Delete failed")
        }
    }

    enum MillsYardsError: Error, LocalizedError {
        case invalidURL
        case networkError(String)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:              return "Invalid server URL"
            case .networkError(let m):     return "Server error: \(m)"
            case .decodingError(let m):    return "Decoding error: \(m)"
            }
        }
    }
}
