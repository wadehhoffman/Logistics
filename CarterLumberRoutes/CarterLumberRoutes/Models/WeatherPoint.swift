import Foundation

struct WeatherPoint: Identifiable {
    let id = UUID()
    let lat: Double
    let lon: Double
    let state: String
    let temperature: Int         // Fahrenheit
    let feelsLike: Int
    let humidity: Int
    let windSpeed: Int           // mph
    let windDirection: Int
    let description: String
    let icon: String             // SF Symbol name
    let weatherCode: Int
    let label: String            // "Start", "Along route", "Destination"

    static func weatherCodeInfo(_ code: Int) -> (desc: String, icon: String) {
        switch code {
        case 0:       return ("Clear Sky", "sun.max.fill")
        case 1...2:   return ("Partly Cloudy", "cloud.sun.fill")
        case 3:       return ("Overcast", "cloud.fill")
        case 4...49:  return ("Foggy", "cloud.fog.fill")
        case 50...57: return ("Drizzle", "cloud.drizzle.fill")
        case 58...67: return ("Rain", "cloud.rain.fill")
        case 68...77: return ("Snow", "cloud.snow.fill")
        case 78...82: return ("Rain Showers", "cloud.heavyrain.fill")
        case 83...86: return ("Snow Showers", "cloud.snow.fill")
        case 87...99: return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:      return ("Unknown", "thermometer.medium")
        }
    }
}
