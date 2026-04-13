import Foundation
import CoreLocation
import SwiftUI

struct Vehicle: Identifiable {
    let id: Int
    let name: String
    let type: VehicleType        // "truck" / "trailer" / "unknown" — from IntelliShift sub-branch
    let descriptionText: String  // vehicleMakeModel — `description` is a reserved name, use renamed
    let lat: Double
    let lon: Double
    let speed: Double
    let heading: Double
    let engineOn: Bool
    let driver: String           // Backward-compat alias: server populates with operator value
    let `operator`: String       // assignedOperatorText from IntelliShift; primary going forward
    let street: String
    let city: String
    let state: String
    let updated: String
    let isSpeeding: Bool
    let stopDuration: Int  // seconds

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Best display name for the assigned person — operator first, fall back to driver.
    var operatorOrDriver: String {
        let op = self.`operator`.trimmingCharacters(in: .whitespaces)
        if !op.isEmpty { return op }
        return driver
    }

    enum VehicleType: String, Codable {
        case truck, trailer, unknown

        var label: String {
            switch self {
            case .truck:   return "Truck (CMV)"
            case .trailer: return "Trailer"
            case .unknown: return "Vehicle"
            }
        }

        var systemImage: String {
            switch self {
            case .truck:   return "truck.box.fill"
            case .trailer: return "rectangle.fill"
            case .unknown: return "questionmark.square.fill"
            }
        }
    }

    var status: TruckStatus {
        if !engineOn { return .stopped }
        if speed > 0 { return .moving }
        return .idle
    }

    var locationDescription: String {
        [street, city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    enum TruckStatus: String, CaseIterable {
        case moving, idle, stopped

        var color: Color {
            switch self {
            case .moving: return .blue
            case .idle: return .orange
            case .stopped: return .red
            }
        }

        var label: String {
            switch self {
            case .moving: return "Moving"
            case .idle: return "Idle"
            case .stopped: return "Stopped"
            }
        }

        var systemImage: String {
            switch self {
            case .moving: return "truck.box.fill"
            case .idle: return "pause.circle.fill"
            case .stopped: return "stop.circle.fill"
            }
        }
    }
}

// Custom Codable to handle flexible JSON types from the server
extension Vehicle: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, type, lat, lon, speed, heading, engineOn, driver
        case street, city, state, updated, isSpeeding, stopDuration
        case description    // server: vehicleMakeModel (renamed for client because Swift reserves `description`)
        case `operator`
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""

        // type defaults to .unknown for back-compat with old server payloads
        if let raw = try c.decodeIfPresent(String.self, forKey: .type),
           let t = VehicleType(rawValue: raw) { type = t } else { type = .unknown }

        descriptionText = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        lat = try c.decodeIfPresent(Double.self, forKey: .lat) ?? 0
        lon = try c.decodeIfPresent(Double.self, forKey: .lon) ?? 0
        engineOn = try c.decodeIfPresent(Bool.self, forKey: .engineOn) ?? false

        // operator preferred, driver fallback. Server populates both with the same value
        // when assignedOperatorText is set, so either field works.
        let op = try c.decodeIfPresent(String.self, forKey: .operator) ?? ""
        let drv = try c.decodeIfPresent(String.self, forKey: .driver) ?? ""
        self.`operator` = op.isEmpty ? drv : op
        driver = drv.isEmpty ? op : drv

        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? ""
        isSpeeding = try c.decodeIfPresent(Bool.self, forKey: .isSpeeding) ?? false

        // speed/heading can be Int or Double
        if let d = try? c.decode(Double.self, forKey: .speed) { speed = d }
        else if let i = try? c.decode(Int.self, forKey: .speed) { speed = Double(i) }
        else { speed = 0 }

        if let d = try? c.decode(Double.self, forKey: .heading) { heading = d }
        else if let i = try? c.decode(Int.self, forKey: .heading) { heading = Double(i) }
        else { heading = 0 }

        // stopDuration can be Int, Double, or String
        if let i = try? c.decode(Int.self, forKey: .stopDuration) { stopDuration = i }
        else if let d = try? c.decode(Double.self, forKey: .stopDuration) { stopDuration = Int(d) }
        else if let s = try? c.decode(String.self, forKey: .stopDuration), let i = Int(s) { stopDuration = i }
        else { stopDuration = 0 }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(type.rawValue, forKey: .type)
        try c.encode(descriptionText, forKey: .description)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(speed, forKey: .speed)
        try c.encode(heading, forKey: .heading)
        try c.encode(engineOn, forKey: .engineOn)
        try c.encode(driver, forKey: .driver)
        try c.encode(self.`operator`, forKey: .operator)
        try c.encode(street, forKey: .street)
        try c.encode(city, forKey: .city)
        try c.encode(state, forKey: .state)
        try c.encode(updated, forKey: .updated)
        try c.encode(isSpeeding, forKey: .isSpeeding)
        try c.encode(stopDuration, forKey: .stopDuration)
    }
}

struct VehiclesResponse: Codable {
    let vehicles: [Vehicle]
    let total: Int
    let withLocation: Int
    let endpoint: String
}
