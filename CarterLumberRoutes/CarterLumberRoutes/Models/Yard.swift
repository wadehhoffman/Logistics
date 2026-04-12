import Foundation
import CoreLocation

struct Yard: Codable, Identifiable, Hashable {
    var id: String { "\(storeNumber)-\(posNumber)" }
    let storeNumber: String
    let posNumber: String
    let storeType: String
    let street: String
    let city: String
    let state: String
    let zip: String
    let lat: Double
    let lon: Double
    let manager: String
    let market: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var displayName: String {
        "#\(posNumber) — \(city), \(state)"
    }

    var fullAddress: String {
        "\(street), \(city), \(state) \(zip)"
    }

    var storeTypeEnum: StoreType {
        StoreType(rawValue: storeType.uppercased()) ?? .unknown
    }

    enum StoreType: String, CaseIterable {
        case lumber = "LUMBER"
        case ccp = "CCP"
        case timber = "TIMBER"
        case truss = "TRUSS"
        case millwork = "MILLWORK"
        case distribution = "DISTRIBUTION"
        case unknown = ""

        var displayName: String {
            switch self {
            case .lumber: return "Lumber"
            case .ccp: return "CCP"
            case .timber: return "Timber"
            case .truss: return "Truss"
            case .millwork: return "Millwork"
            case .distribution: return "Distribution"
            case .unknown: return "Other"
            }
        }
    }
}
