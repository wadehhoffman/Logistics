import Foundation

struct FuelEstimate {
    let gallonsNeeded: Double
    let fuelStops: Int
    let averagePrice: Double?
    let totalCost: Double?
    let perStateBreakdown: [StateFuelDetail]

    var formattedTotalCost: String {
        guard let cost = totalCost else { return "N/A" }
        return String(format: "$%.2f", cost)
    }

    var formattedGallons: String {
        String(format: "%.1f gal", gallonsNeeded)
    }

    var formattedAveragePrice: String {
        guard let price = averagePrice else { return "N/A" }
        return String(format: "$%.3f/gal", price)
    }
}

struct StateFuelDetail: Identifiable {
    let id = UUID()
    let stateCode: String
    let stateName: String
    let pricePerGallon: Double
    let priceDate: String
    let miles: Double
    let gallons: Double
    let estimatedCost: Double
}

struct StateMileage {
    let state: String
    let miles: Double
    let fraction: Double
}
