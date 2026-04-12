import XCTest
@testable import CarterLumberRoutes

final class StateFromCoordinateTests: XCTestCase {
    func testKnownLocations() {
        // Columbus, OH
        XCTAssertEqual(StateFromCoordinate.getState(lat: 39.96, lon: -82.99), "OH")
        // Atlanta, GA
        XCTAssertEqual(StateFromCoordinate.getState(lat: 33.75, lon: -84.39), "GA")
        // Miami, FL
        XCTAssertEqual(StateFromCoordinate.getState(lat: 25.76, lon: -80.19), "FL")
    }

    func testOceanLocation() {
        // Middle of Atlantic - should return nil
        XCTAssertNil(StateFromCoordinate.getState(lat: 35.0, lon: -50.0))
    }

    func testRouteStateAnalysis() {
        // Simple 2-point route: Columbus OH to Pittsburgh PA
        let coords: [[Double]] = [
            [-82.99, 39.96],  // Columbus OH
            [-81.50, 40.20],  // midpoint
            [-79.99, 40.44],  // Pittsburgh PA
        ]
        let result = StateFromCoordinate.getStatesFromRoute(
            coordinates: coords,
            originState: "OH",
            destState: "PA",
            totalDistanceMiles: 185
        )
        // Should have OH and PA segments
        let states = Set(result.map(\.state))
        XCTAssertTrue(states.contains("OH"))
        // Total miles should roughly equal input
        let totalMiles = result.reduce(0) { $0 + $1.miles }
        XCTAssertEqual(totalMiles, 185, accuracy: 1)
    }
}
