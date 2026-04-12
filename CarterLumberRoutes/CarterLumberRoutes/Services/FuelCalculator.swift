import Foundation

enum FuelCalculator {
    static func calculate(
        distanceMiles: Double,
        stateBreakdown: [StateMileage],
        dieselPrices: [String: DieselPrice],
        mpg: Double,
        tankSizeGallons: Double
    ) -> FuelEstimate {
        let gallons = distanceMiles / mpg
        let stops = max(0, Int(ceil(gallons / tankSizeGallons)) - 1)

        guard !dieselPrices.isEmpty else {
            return FuelEstimate(
                gallonsNeeded: gallons,
                fuelStops: stops,
                averagePrice: nil,
                totalCost: nil,
                perStateBreakdown: []
            )
        }

        var totalCost = 0.0
        var totalWeightedPrice = 0.0
        var totalWeightedMiles = 0.0
        var perState: [StateFuelDetail] = []

        if !stateBreakdown.isEmpty {
            for seg in stateBreakdown {
                if let priceInfo = dieselPrices[seg.state] {
                    let segGallons = seg.miles / mpg
                    let segCost = segGallons * priceInfo.price
                    totalCost += segCost
                    totalWeightedPrice += priceInfo.price * seg.miles
                    totalWeightedMiles += seg.miles
                    perState.append(StateFuelDetail(
                        stateCode: seg.state,
                        stateName: FormatHelpers.stateName(for: seg.state),
                        pricePerGallon: priceInfo.price,
                        priceDate: priceInfo.date,
                        miles: seg.miles,
                        gallons: segGallons,
                        estimatedCost: segCost
                    ))
                }
            }
        }

        let avgPrice = totalWeightedMiles > 0 ? totalWeightedPrice / totalWeightedMiles : nil

        // Fallback: use simple average if no per-state data
        if perState.isEmpty && !dieselPrices.isEmpty {
            let prices = dieselPrices.values.map(\.price)
            let avg = prices.reduce(0, +) / Double(prices.count)
            let cost = gallons * avg
            return FuelEstimate(
                gallonsNeeded: gallons,
                fuelStops: stops,
                averagePrice: avg,
                totalCost: cost,
                perStateBreakdown: []
            )
        }

        return FuelEstimate(
            gallonsNeeded: gallons,
            fuelStops: stops,
            averagePrice: avgPrice,
            totalCost: totalCost,
            perStateBreakdown: perState
        )
    }
}
