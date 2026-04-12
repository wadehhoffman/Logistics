import Foundation
import CoreLocation
import SwiftUI

@MainActor @Observable
final class SingleRouteViewModel {
    // Selection
    var selectedMill: Mill?
    var selectedYard: Yard?
    var millCoordinate: CLLocationCoordinate2D?

    // Results
    var routeResult: RouteResult?
    var fuelEstimate: FuelEstimate?
    var weatherPoints: [WeatherPoint] = []
    var stateBreakdown: [StateMileage] = []

    // UI State
    var isGeocodingMill = false
    var isCalculating = false
    var isFetchingWeather = false
    var weatherProgress: Double = 0
    var errorMessage: String?

    // Dependencies
    private let routingService: MapboxRoutingService
    private let geocodingService: GeocodingService
    private let dieselService: DieselPriceService
    private let weatherService: WeatherService
    private let config: AppConfiguration

    var canCalculate: Bool {
        millCoordinate != nil && selectedYard != nil && !isCalculating
    }

    init(config: AppConfiguration) {
        self.config = config
        self.routingService = MapboxRoutingService(mapboxToken: config.mapboxToken)
        self.geocodingService = GeocodingService()
        self.dieselService = DieselPriceService()
        self.weatherService = WeatherService()
    }

    func selectMill(_ mill: Mill) async {
        selectedMill = mill
        millCoordinate = nil
        errorMessage = nil
        isGeocodingMill = true
        defer { isGeocodingMill = false }

        do {
            millCoordinate = try await geocodingService.geocode(address: mill.address)
        } catch {
            errorMessage = "Could not locate mill: \(error.localizedDescription)"
        }
    }

    func calculateRoute() async {
        guard let millCoord = millCoordinate, let yard = selectedYard else { return }
        isCalculating = true
        errorMessage = nil
        routeResult = nil
        fuelEstimate = nil
        weatherPoints = []
        stateBreakdown = []
        defer { isCalculating = false }

        do {
            // Step 1: Calculate route
            let result = try await routingService.calculateRoute(
                waypoints: [millCoord, yard.coordinate]
            )
            routeResult = result

            // Step 2: Analyze states along route (for fuel pricing)
            if let geometry = result.geometry {
                stateBreakdown = StateFromCoordinate.getStatesFromRoute(
                    coordinates: geometry.coordinates,
                    originState: selectedMill?.state,
                    destState: yard.state,
                    totalDistanceMiles: result.distanceMiles
                )
            }

            // Step 3: Fetch diesel prices and weather in parallel
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchDieselPrices() }
                group.addTask { await self.fetchWeather() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchDieselPrices() async {
        let stateCodes = stateBreakdown.map(\.state)
        guard !stateCodes.isEmpty, !config.eiaApiKey.isEmpty else { return }

        do {
            let prices = try await dieselService.fetchPrices(
                stateCodes: stateCodes,
                apiKey: config.eiaApiKey
            )
            guard let route = routeResult else { return }
            fuelEstimate = FuelCalculator.calculate(
                distanceMiles: route.distanceMiles,
                stateBreakdown: stateBreakdown,
                dieselPrices: prices,
                mpg: config.truckMPG,
                tankSizeGallons: config.tankSizeGallons
            )
        } catch {
            print("Diesel price error: \(error)")
        }
    }

    private func fetchWeather() async {
        guard let geometry = routeResult?.geometry else { return }
        isFetchingWeather = true
        defer { isFetchingWeather = false }

        weatherPoints = await weatherService.fetchWeatherAlongRoute(
            coordinates: geometry.coordinates,
            onProgress: { @Sendable [weak self] done, total in
                Task { @MainActor in
                    self?.weatherProgress = Double(done) / Double(total)
                }
            }
        )
    }

    func clearRoute() {
        routeResult = nil
        fuelEstimate = nil
        weatherPoints = []
        stateBreakdown = []
        errorMessage = nil
    }

    func clearAll() {
        selectedMill = nil
        selectedYard = nil
        millCoordinate = nil
        clearRoute()
    }
}
