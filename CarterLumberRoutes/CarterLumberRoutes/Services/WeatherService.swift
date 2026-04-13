import Foundation
import CoreLocation

/// Weather-along-route client. Now routes through our server's /api/weather
/// proxy which builds the full Open-Meteo query server-side; iOS only sends
/// lat/lon. Response shape and caching behavior are unchanged.
actor WeatherService {
    private let baseURL: String
    private var cache: [String: WeatherPoint] = [:]
    private let session: URLSession

    init(baseURL: String = "http://logistics-ai.carterlumber.com") {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    /// Fetch weather at sampled points along a route.
    /// Returns up to 5 weather points (start, intermediate, end).
    func fetchWeatherAlongRoute(
        coordinates: [[Double]],
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [WeatherPoint] {
        guard coordinates.count >= 2 else { return [] }

        let pointCount = min(5, max(3, coordinates.count / 100 + 1))
        var samplePoints: [(lat: Double, lon: Double, label: String)] = []

        for i in 0..<pointCount {
            let idx = Int(Double(i) / Double(pointCount - 1) * Double(coordinates.count - 1))
            let lat = coordinates[idx][1]
            let lon = coordinates[idx][0]
            let label: String
            if i == 0 { label = "Start" }
            else if i == pointCount - 1 { label = "Destination" }
            else { label = "Along route" }
            samplePoints.append((lat, lon, label))
        }

        var results: [WeatherPoint] = []
        for (i, pt) in samplePoints.enumerated() {
            let cacheKey = "\(String(format: "%.2f", pt.lat)),\(String(format: "%.2f", pt.lon))"

            if let cached = cache[cacheKey] {
                results.append(cached)
                onProgress(i + 1, pointCount)
                continue
            }

            if let weather = try? await fetchWeather(lat: pt.lat, lon: pt.lon, label: pt.label) {
                cache[cacheKey] = weather
                results.append(weather)
            }
            onProgress(i + 1, pointCount)
        }

        return results
    }

    private func fetchWeather(lat: Double, lon: Double, label: String) async throws -> WeatherPoint {
        // Server fills in the rest of the Open-Meteo query (units, fields, forecast_days).
        let urlStr = "\(baseURL)/api/weather" +
            "?lat=\(String(format: "%.4f", lat))" +
            "&lon=\(String(format: "%.4f", lon))"

        guard let url = URL(string: urlStr) else { throw WeatherError.invalidURL }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.networkError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else {
            throw WeatherError.parseError
        }

        let weatherCode = current["weather_code"] as? Int ?? 0
        let info = WeatherPoint.weatherCodeInfo(weatherCode)
        let state = StateFromCoordinate.getState(lat: lat, lon: lon) ?? "??"

        return WeatherPoint(
            lat: lat, lon: lon,
            state: state,
            temperature: Int(current["temperature_2m"] as? Double ?? 0),
            feelsLike: Int(current["apparent_temperature"] as? Double ?? 0),
            humidity: Int(current["relative_humidity_2m"] as? Double ?? 0),
            windSpeed: Int(current["wind_speed_10m"] as? Double ?? 0),
            windDirection: Int(current["wind_direction_10m"] as? Double ?? 0),
            description: info.desc,
            icon: info.icon,
            weatherCode: weatherCode,
            label: label
        )
    }

    enum WeatherError: Error {
        case invalidURL, networkError, parseError
    }
}
