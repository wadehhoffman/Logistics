import Foundation
import CoreLocation
import SwiftUI

struct Vehicle: Codable, Identifiable {
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
    let stopDuration: String

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

struct VehiclesResponse: Codable {
    let vehicles: [Vehicle]
    let total: Int
    let withLocation: Int
    let endpoint: String
}
