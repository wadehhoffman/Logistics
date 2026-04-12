import Foundation
import CoreLocation

struct Mill: Codable, Identifiable, Hashable {
    var id: String { "\(vendor)-\(name)" }
    let name: String
    let product: String
    let vendor: String
    let street: String
    let city: String
    let stateZip: String
    let address: String

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
