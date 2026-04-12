import XCTest
@testable import CarterLumberRoutes

final class HaversineTests: XCTestCase {
    func testKnownDistance() {
        // New York to Los Angeles ~3940 km
        let dist = Haversine.distance(lat1: 40.7128, lon1: -74.0060, lat2: 34.0522, lon2: -118.2437)
        XCTAssertEqual(dist, 3940, accuracy: 50) // within 50km
    }

    func testZeroDistance() {
        let dist = Haversine.distance(lat1: 40.0, lon1: -80.0, lat2: 40.0, lon2: -80.0)
        XCTAssertEqual(dist, 0, accuracy: 0.001)
    }

    func testFallbackRoute() {
        let from = CLLocationCoordinate2D(latitude: 40.0, longitude: -80.0)
        let to = CLLocationCoordinate2D(latitude: 41.0, longitude: -81.0)
        let result = Haversine.fallbackRoute(from: from, to: to)

        XCTAssertTrue(result.isFallback)
        XCTAssertGreaterThan(result.distance, 0)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertNotNil(result.geometry)
        XCTAssertEqual(result.geometry?.coordinates.count, 21) // 0 to 20 = 21 points
    }
}
