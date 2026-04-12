import Foundation
import CoreLocation
import SwiftUI

struct Vehicle: Identifiable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    let speed: Double
    let heading: Double
    let engineOn: Bool
    let driver: String
    let street: String
    let city: String
    let state: String
    let updated: String
    let isSpeeding: Bool
    let stopDuration: Int  // seconds

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
        case id, name, lat, lon, speed, heading, engineOn, driver
        case street, city, state, updated, isSpeeding, stopDuration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lat = try c.decodeIfPresent(Double.self, forKey: .lat) ?? 0
        lon = try c.decodeIfPresent(Double.self, forKey: .lon) ?? 0
        engineOn = try c.decodeIfPresent(Bool.self, forKey: .engineOn) ?? false
        driver = try c.decodeIfPresent(String.self, forKey: .driver) ?? ""
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
}

struct VehiclesResponse: Codable {
    let vehicles: [Vehicle]
    let total: Int
    let withLocation: Int
    let endpoint: String
}
