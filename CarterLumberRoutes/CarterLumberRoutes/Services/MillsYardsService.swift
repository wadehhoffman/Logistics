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
