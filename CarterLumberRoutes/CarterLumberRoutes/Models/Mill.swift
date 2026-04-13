import Foundation
import CoreLocation

struct Mill: Codable, Identifiable, Hashable {
    /// Stable client id when uuid is present (server-assigned), otherwise vendor+name composite.
    var id: String { uuid ?? "\(vendor)-\(name)" }

    let uuid: String?           // server-assigned (Phase iA — present after Mills are sourced from /api/mills)
    let name: String
    let product: String
    let vendor: String
    let street: String
    let city: String
    let stateZip: String
    let address: String
    let lat: Double?            // optional — populated by server geocode-all backfill
    let lon: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var state: String {
        let parts = stateZip.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.first.map(String.init) ?? ""
    }

    var zip: String {
        let parts = stateZip.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : ""
    }

    var displayName: String {
        "\(name) (\(product))"
    }

    var shortName: String {
        "\(name) — \(city), \(state)"
    }

    var productType: ProductType {
        ProductType(rawValue: product.uppercased()) ?? .unknown
    }

    enum ProductType: String, CaseIterable {
        case yp = "YP"
        case osb = "OSB"
        case unknown = ""

        var displayName: String {
            switch self {
            case .yp: return "Yellow Pine"
            case .osb: return "OSB"
            case .unknown: return "Other"
            }
        }
    }
}
