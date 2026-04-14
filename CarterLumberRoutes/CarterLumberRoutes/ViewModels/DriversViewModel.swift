import Foundation
import SwiftUI

@MainActor
@Observable
final class DriversViewModel {
    var drivers: [Driver] = []
    var searchText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var asOf: String?

    private let service: DriversService

    init(config: AppConfiguration) {
        self.service = DriversService(baseURL: config.intelliShiftBaseURL)
    }

    // MARK: - Derived

    var filteredDrivers: [Driver] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let all = drivers
        guard !q.isEmpty else { return all }
        return all.filter { d in
            d.name.lowercased().contains(q)
                || d.employeeId.lowercased().contains(q)
                || (d.currentVehicle?.name ?? "").lowercased().contains(q)
                || (d.currentVehicle?.locationLabel ?? "").lowercased().contains(q)
        }
    }

    var onShiftCount: Int  { drivers.filter { $0.status == .onShift }.count }
    var offShiftCount: Int { drivers.filter { $0.status == .offShift }.count }

    var averageWeekHours: Double {
        guard !drivers.isEmpty else { return 0 }
        return drivers.reduce(0) { $0 + $1.weekActualHours } / Double(drivers.count)
    }

    var lowDailyCount: Int {
        drivers.filter { $0.status == .onShift && $0.dailyRemaining < 2 }.count
    }

    var expiredMedCardCount: Int {
        drivers.filter { $0.medicalCardStatus == .expired }.count
    }

    var expiringMedCardCount: Int {
        drivers.filter { $0.medicalCardStatus == .expiringSoon }.count
    }

    var asOfLabel: String {
        guard let str = asOf else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: str) else { return str }
        let tf = DateFormatter()
        tf.timeStyle = .medium
        return tf.string(from: date)
    }

    // MARK: - Loading

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await service.fetchDrivers()
            drivers = response.drivers
            asOf = response.asOf
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
