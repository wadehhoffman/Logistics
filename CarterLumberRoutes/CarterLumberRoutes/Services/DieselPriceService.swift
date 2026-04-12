import Foundation

actor DieselPriceService {
    private var cache: [String: DieselPrice] = [:] // state code → price
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    /// Fetch diesel prices for the given state codes from EIA API.
    /// Returns a dictionary of state code → DieselPrice.
    func fetchPrices(stateCodes: [String], apiKey: String) async throws -> [String: DieselPrice] {
        guard !apiKey.isEmpty else { return [:] }

        // Filter to states we haven't cached
        let needed = stateCodes.filter { cache[$0] == nil }

        if needed.isEmpty {
            return stateCodes.reduce(into: [:]) { result, state in
                result[state] = cache[state]
            }
        }

        // Determine unique PADD codes needed
        var paddSet = Set<String>()
        for state in needed {
            if let padd = PADDRegion.region(for: state) {
                paddSet.insert(padd.rawValue)
            }
        }
        let paddCodes = Array(paddSet)
        guard !paddCodes.isEmpty else { return [:] }

        // Build EIA API URL
        let duoareaParams = paddCodes.map { "facets[duoarea][]=\($0)" }.joined(separator: "&")
        let urlStr = "https://api.eia.gov/v2/petroleum/pri/gnd/data/" +
            "?api_key=\(apiKey)" +
            "&frequency=weekly&data[0]=value" +
            "&facets[product][]=EPD2D" +
            "&\(duoareaParams)" +
            "&sort[0][column]=period&sort[0][direction]=desc&length=50"

        guard let url = URL(string: urlStr) else {
            throw DieselError.invalidURL
        }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DieselError.networkError
        }

        if httpResponse.statusCode == 403 {
            throw DieselError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw DieselError.networkError
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = json["response"] as? [String: Any],
              let rows = responseObj["data"] as? [[String: Any]] else {
            throw DieselError.parseError
        }

        // Get most recent price per PADD region
        var paddPrices: [String: (price: Double, date: String)] = [:]
        for row in rows {
            guard let eiaCode = row["duoarea"] as? String,
                  let value = row["value"] as? Double,
                  let period = row["period"] as? String,
                  paddPrices[eiaCode] == nil else { continue }
            paddPrices[eiaCode] = (value, period)
        }

        // Map PADD prices back to each state
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

        return stateCodes.reduce(into: [:]) { result, state in
            result[state] = cache[state]
        }
    }

    func clearCache() {
        cache.removeAll()
    }

    enum DieselError: Error, LocalizedError {
        case invalidURL
        case invalidAPIKey
        case networkError
        case parseError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid EIA API URL"
            case .invalidAPIKey: return "Invalid EIA API key"
            case .networkError: return "EIA API unavailable"
            case .parseError: return "Failed to parse diesel price data"
            }
        }
    }
}
