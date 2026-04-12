import XCTest
@testable import CarterLumberRoutes

final class FuelCalculatorTests: XCTestCase {
    func testBasicCalculation() {
        let breakdown = [
            StateMileage(state: "OH", miles: 200, fraction: 0.5),
            StateMileage(state: "PA", miles: 200, fraction: 0.5),
        ]
        let prices: [String: DieselPrice] = [
            "OH": DieselPrice(price: 3.50, date: "2026-04-07", region: "Midwest"),
            "PA": DieselPrice(price: 3.80, date: "2026-04-07", region: "Central Atlantic"),
        ]

        let result = FuelCalculator.calculate(
            distanceMiles: 400,
            stateBreakdown: breakdown,
            dieselPrices: prices,
            mpg: 6.5,
            tankSizeGallons: 150
        )

        // 400 mi / 6.5 mpg = ~61.5 gallons
        XCTAssertEqual(result.gallonsNeeded, 400 / 6.5, accuracy: 0.1)
        // No fuel stops needed (61.5 gal < 150 gal tank)
        XCTAssertEqual(result.fuelStops, 0)
        // Cost: (200/6.5)*3.50 + (200/6.5)*3.80
        let expectedCost = (200 / 6.5) * 3.50 + (200 / 6.5) * 3.80
        XCTAssertEqual(result.totalCost!, expectedCost, accuracy: 0.01)
    }

    func testNoPricesAvailable() {
        let result = FuelCalculator.calculate(
            distanceMiles: 400,
            stateBreakdown: [],
            dieselPrices: [:],
            mpg: 6.5,
            tankSizeGallons: 150
        )
        XCTAssertNil(result.totalCost)
        XCTAssertTrue(result.perStateBreakdown.isEmpty)
    }

    func testFuelStopsRequired() {
        let result = FuelCalculator.calculate(
            distanceMiles: 2000,
            stateBreakdown: [StateMileage(state: "OH", miles: 2000, fraction: 1.0)],
            dieselPrices: ["OH": DieselPrice(price: 3.50, date: "2026-04-07", region: "Midwest")],
            mpg: 6.5,
            tankSizeGallons: 150
        )
        // 2000/6.5 = ~307 gallons, 307/150 = ~2.05, ceil = 3, minus 1 = 2 stops
        XCTAssertEqual(result.fuelStops, 2)
    }
}
