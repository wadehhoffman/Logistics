import Foundation

/// Branch 570 operator with live HOS tracking, vehicle assignment, and
/// compliance data. Decoded from GET /api/drivers on our server, which
/// aggregates IntelliShift operator + assignment + schedule data.
struct Driver: Codable, Identifiable {
    let id: Int
    let name: String
    let firstName: String
    let lastName: String
    let employeeId: String
    let status: ShiftStatus
    let todayActualHours: Double
    let weekActualHours: Double
    let weekPlannedHours: Double
    let dailyRemaining: Double
    let weeklyRemaining: Double
    let hosSchedule: String             // "70/8" or "60/7"
    let currentVehicle: DriverVehicle?
    let shiftStartTime: String?
    let medicalCardExpiration: String?
    let medicalCardStatus: MedCardStatus
    let endorsements: [String]

    enum ShiftStatus: String, Codable {
        case onShift  = "on-shift"
        case offShift = "off-shift"
    }

    enum MedCardStatus: String, Codable {
        case valid
        case expiringSoon = "expiring-soon"
        case expired
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = MedCardStatus(rawValue: raw) ?? .unknown
        }
    }

    /// Formatted shift start, e.g. "7:47 AM"
    var shiftStartLabel: String? {
        guard let str = shiftStartTime else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: str) ?? {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            return df.date(from: str)
        }()
        guard let d = date else { return nil }
        let tf = DateFormatter()
        tf.timeStyle = .short
        return tf.string(from: d)
    }

    /// Medical card expiry as a formatted date string
    var medCardDateLabel: String? {
        guard let str = medicalCardExpiration else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let date = iso.date(from: str) ?? {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return df.date(from: str)
        }()
        guard let d = date else { return str.prefix(10).description }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: d)
    }
}

struct DriverVehicle: Codable {
    let id: Int
    let name: String
    let lat: Double?
    let lon: Double?
    let city: String?
    let state: String?
    let engineOn: Bool?
    let speed: Double?

    var locationLabel: String {
        [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct DriversResponse: Codable {
    let drivers: [Driver]
    let total: Int
    let asOf: String
}
