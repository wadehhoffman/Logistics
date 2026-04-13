import Foundation

/// Diesel price fetcher that now routes EIA requests through our server proxy
/// (/api/diesel) instead of calling EIA directly. Server passes the query
/// through unchanged, so the client still supplies its EIA api_key param.
/// Caching, parsing, and error handling are unchanged from the direct-call
/// version — we've only substituted the base URL.
actor DieselPriceService {
    private let baseURL: String
    private var cache: [String: DieselPrice] = [:] // state code → price
    private let session: URLSession

    init(baseURL: String = "http://logistics-ai.carterlumber.com") {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetch diesel prices for the given state codes.
    /// Returns a dictionary of state code → DieselPrice.
    func fetchPrices(stateCodes: [String], apiKey: String) async throws -> [String: DieselPrice] {
        guard !apiKey.isEmpty else { return [:] }

        let needed = stateCodes.filter { cache[$0] == nil }
        if needed.isEmpty {
            return stateCodes.reduce(into: [:]) { result, state in result[state] = cache[state] }
        }

        var paddSet = Set<String>()
        for state in needed {
            if let padd = PADDRegion.region(for: state) { paddSet.insert(padd.rawValue) }
        }
        let paddCodes = Array(paddSet)
        guard !paddCodes.isEmpty else { return [:] }

        // Build the EIA-format query string, same shape as before — the server
        // forwards it untouched to api.eia.gov. Encode the api_key value so
        // odd characters don't break the URL.
        let duoareaParams = paddCodes.map { "facets[duoarea][]=\($0)" }.joined(separator: "&")
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let qs = "api_key=\(encodedKey)" +
                 "&frequency=weekly&data[0]=value" +
                 "&facets[product][]=EPD2D" +
                 "&\(duoareaParams)" +
                 "&sort[0][column]=period&sort[0][direction]=desc&length=50"

        guard let url = URL(string: "\(baseURL)/api/diesel?\(qs)") else {
            throw DieselError.invalidURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw DieselError.networkError }
        if http.statusCode == 403 { throw DieselError.invalidAPIKey }
        guard http.statusCode == 200 else { throw DieselError.networkError }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = json["response"] as? [String: Any],
              let rows = responseObj["data"] as? [[String: Any]] else {
            throw DieselError.parseError
        }

        // Most recent price per PADD region
        var paddPrices: [String: (price: Double, date: String)] = [:]
        for row in rows {
            guard let eiaCode = row["duoarea"] as? String,
                  let value = row["value"] as? Double,
                  let period = row["period"] as? String,
                  paddPrices[eiaCode] == nil else { continue }
            paddPrices[eiaCode] = (value, period)
        }

        for state in needed {
            if let padd = PADDRegion.region(for: state),
               let priceData = paddPrices[padd.rawValue] {
                cache[state] = DieselPrice(
                    price: priceData.price,
                    date: priceData.date,
                    region: padd.displayName
                )
            }
        }

        return stateCodes.reduce(into: [:]) { result, state in result[state] = cache[state] }
    }

    func clearCache() { cache.removeAll() }

    enum DieselError: Error, LocalizedError {
        case invalidURL
        case invalidAPIKey
        case networkError
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidURL:    return "Invalid diesel-price URL"
            case .invalidAPIKey: return "Invalid EIA API key"
            case .networkError:  return "EIA proxy unavailable"
            case .parseError:    return "Failed to parse diesel price data"
            }
        }
    }
}
