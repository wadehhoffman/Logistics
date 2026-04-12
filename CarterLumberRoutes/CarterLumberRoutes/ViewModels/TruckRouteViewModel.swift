import Foundation
import CoreLocation
import SwiftUI

@MainActor @Observable
final class TruckRouteViewModel {
    // Selection
    var vehicles: [Vehicle] = []
    var selectedVehicle: Vehicle?
    var selectedMill: Mill?
    var selectedYard: Yard?
    var millCoordinate: CLLocationCoordinate2D?

    // Results
    var twoLegRoute: TwoLegRoute?
    var fuelEstimate: FuelEstimate?
    var weatherPoints: [WeatherPoint] = []
    var stateBreakdown: [StateMileage] = []

    // UI State
    var isLoadingTrucks = false
    var isGeocodingMill = false
    var isCalculating = false
    var errorMessage: String?

    // Dependencies
    private let routingService: MapboxRoutingService
    private let geocodingService: GeocodingService
    private let dieselService: DieselPriceService
    private let weatherService: WeatherService
    private let intelliShiftService: IntelliShiftService
    private let config: AppConfiguration

    var canCalculate: Bool {
        selectedVehicle != nil && millCoordinate != nil && selectedYard != nil && !isCalculating
    }

    init(config: AppConfiguration) {
        self.config = config
        self.routingService = MapboxRoutingService(mapboxToken: config.mapboxToken)
        self.geocodingService = GeocodingService()
        self.dieselService = DieselPriceService()
        self.weatherService = WeatherService()
        self.intelliShiftService = IntelliShiftService(baseURL: config.intelliShiftBaseURL)
    }

    func loadTrucks() async {
        isLoadingTrucks = true
        errorMessage = nil
        defer { isLoadingTrucks = false }

        do {
            vehicles = try await intelliShiftService.fetchVehicles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectMill(_ mill: Mill) async {
        selectedMill = mill
        millCoordinate = nil
        isGeocodingMill = true
        defer { isGeocodingMill = false }

        do {
            millCoordinate = try await geocodingService.geocode(address: mill.address)
        } catch {
            errorMessage = "Could not locate mill: \(error.localizedDescription)"
        }
    }

    func calculateTruckRoute() async {
        guard let vehicle = selectedVehicle,
              let millCoord = millCoordinate,
              let yard = selectedYard else { return }

        isCalculating = true
        errorMessage = nil
        twoLegRoute = nil
        fuelEstimate = nil
        weatherPoints = []
        defer { isCalculating = false }

        do {
            let waypoints = [vehicle.coordinate, millCoord, yard.coordinate]
            let legNames = [
                (from: vehicle.name, to: selectedMill?.name ?? "Mill"),
                (from: selectedMill?.name ?? "Mill", to: yard.displayName),
            ]

            let (legs, combinedGeometry) = try await routingService.calculateRouteWithLegs(
                waypoints: waypoints,
                legNames: legNames
            )

            let route: TwoLegRoute
            if legs.count >= 2 {
                route = TwoLegRoute(leg1: legs[0], leg2: legs[1], combinedGeometry: combinedGeometry)
            } else {
                // Fallback: single leg
                let singleLeg = legs[0]
                route = TwoLegRoute(
                    leg1: RouteLeg(from: legNames[0].from, to: legNames[0].to,
                                   distance: singleLeg.distance / 2, duration: singleLeg.duration / 2,
                                   geometry: nil),
                    leg2: RouteLeg(from: legNames[1].from, to: legNames[1].to,
                                   distance: singleLeg.distance / 2, duration: singleLeg.duration / 2,
                                   geometry: nil),
                    combinedGeometry: combinedGeometry
                )
            }
            twoLegRoute = route

            // Analyze states along route
            if let geometry = combinedGeometry {
                let truckState = StateFromCoordinate.getState(
                    lat: vehicle.coordinate.latitude,
                    lon: vehicle.coordinate.longitude
                )
                stateBreakdown = StateFromCoordinate.getStatesFromRoute(
                    coordinates: geometry.coordinates,
                    originState: truckState,
                    destState: yard.state,
                    totalDistanceMiles: route.totalDistanceMiles
                )
            }

            // Fetch diesel and weather in parallel
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchDieselPrices(totalMiles: route.totalDistanceMiles) }
                group.addTask { await self.fetchWeather(geometry: combinedGeometry) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchDieselPrices(totalMiles: Double) async {
        let stateCodes = stateBreakdown.map(\.state)
        guard !stateCodes.isEmpty, !config.eiaApiKey.isEmpty else { return }

        if let prices = try? await dieselService.fetchPrices(stateCodes: stateCodes, apiKey: config.eiaApiKey) {
            fuelEstimate = FuelCalculator.calculate(
                distanceMiles: totalMiles,
                stateBreakdown: stateBreakdown,
                dieselPrices: prices,
                mpg: config.truckMPG,
                tankSizeGallons: config.tankSizeGallons
            )
        }
    }

    private func fetchWeather(geometry: RouteGeometry?) async {
        guard let geometry = geometry else { return }
        weatherPoints = await weatherService.fetchWeatherAlongRoute(coordinates: geometry.coordinates)
    }

    func clearRoute() {
        twoLegRoute = nil
        fuelEstimate = nil
        weatherPoints = []
        stateBreakdown = []
        errorMessage = nil
    }
}
