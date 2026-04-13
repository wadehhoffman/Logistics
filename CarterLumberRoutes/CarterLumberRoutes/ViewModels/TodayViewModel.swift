import Foundation
import SwiftUI

/// View model for the Today dispatcher dashboard.
///
/// Owns the selected date, today's scheduled routes, and the live vehicle
/// feed. Refreshes vehicles automatically every 60 seconds while the view
/// is foregrounded. Routes reload whenever the date changes.
@MainActor
@Observable
final class TodayViewModel {
    // State
    var selectedDate: Date = Date()
    var routes: [ScheduledRoute] = []
    var vehicles: [Vehicle] = []
    var vehicleFilter: String = ""
    var isLoadingRoutes: Bool = false
    var isLoadingVehicles: Bool = false
    var lastError: String?

    // Dependencies
    private let config: AppConfiguration
    private let scheduleService: ScheduleService
    private let intelliShiftService: IntelliShiftService

    // Auto-refresh timer for vehicles — runs only while the view is active
    private var refreshTask: Task<Void, Never>?

    init(config: AppConfiguration) {
        self.config = config
        self.scheduleService = ScheduleService(baseURL: config.intelliShiftBaseURL)
        self.intelliShiftService = IntelliShiftService(baseURL: config.intelliShiftBaseURL)
    }

    // MARK: - Derived

    /// YYYY-MM-DD string used as the ?date=... query param and for dayKey matching.
    var selectedDateKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: selectedDate)
    }

    var selectedDateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: selectedDate)
    }

    var isSelectedDateToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Routes for the selected date, chronologically.
    var sortedRoutes: [ScheduledRoute] {
        routes.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Vehicles matching the filter, trucks first then trailers, alphabetically.
    var filteredVehicles: [Vehicle] {
        let f = vehicleFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [Vehicle]
        if f.isEmpty {
            filtered = vehicles
        } else {
            filtered = vehicles.filter { v in
                v.name.lowercased().contains(f)
                    || v.operatorOrDriver.lowercased().contains(f)
                    || v.city.lowercased().contains(f)
                    || v.state.lowercased().contains(f)
                    || v.type.rawValue.contains(f)
            }
        }
        return filtered.sorted { a, b in
            if a.type != b.type { return a.type == .truck }
            return a.name < b.name
        }
    }

    var truckCount: Int   { vehicles.filter { $0.type == .truck   }.count }
    var trailerCount: Int { vehicles.filter { $0.type == .trailer }.count }

    // MARK: - Date navigation

    func stepDay(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        Task { await loadRoutes() }
    }

    func jumpToToday() {
        selectedDate = Date()
        Task { await loadRoutes() }
    }

    // MARK: - Loading

    func loadAll() async {
        async let r: Void = loadRoutes()
        async let v: Void = loadVehicles()
        _ = await (r, v)
    }

    func loadRoutes() async {
        isLoadingRoutes = true
        defer { isLoadingRoutes = false }
        do {
            // Server supports ?date=YYYY-MM-DD; fall back to ?month if date filter
            // ever regresses (future-proofing).
            let monthStr = String(selectedDateKey.prefix(7))
            let all = try await scheduleService.fetchSchedules(month: monthStr)
            routes = all.filter { $0.dayKey == selectedDateKey }
        } catch {
            lastError = "Routes: \(error.localizedDescription)"
            routes = []
        }
    }

    func loadVehicles() async {
        isLoadingVehicles = true
        defer { isLoadingVehicles = false }
        do {
            vehicles = try await intelliShiftService.fetchVehicles()
        } catch {
            lastError = "Vehicles: \(error.localizedDescription)"
            // Keep the stale list rather than wiping — user can see last-known positions offline
        }
    }

    // MARK: - Auto-refresh (60s for vehicles)

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.loadVehicles()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
