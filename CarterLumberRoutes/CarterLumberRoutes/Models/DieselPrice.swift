import Foundation

struct DieselPrice: Codable {
    let price: Double       // dollars per gallon
    let date: String        // "2026-04-07" weekly period
    let region: String      // "Lower Atlantic"
}
