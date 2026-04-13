import Foundation
import SwiftUI

@MainActor @Observable
final class ScheduleViewModel {
    var allSchedules: [ScheduledRoute] = []
    var selectedDate: Date = Date()
    var isLoading = false
    var errorMessage: String?

    private let service: ScheduleService

    /// Schedules filtered to the selected date
    var filteredSchedules: [ScheduledRoute] {
        let dayKey = dayKeyFor(selectedDate)
        return allSchedules.filter { $0.dayKey == dayKey }
    }

    var selectedDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: selectedDate)
    }

    /// All truck IDs that are already assigned on the selected date (status = "scheduled")
    func trucksScheduledOn(date: String) -> Set<String> {
        let daySchedules = allSchedules.filter { $0.dayKey == date && $0.status == "scheduled" }
        var ids = Set<String>()
        for s in daySchedules {
            if let truckId = s.truck?.id, !truckId.isEmpty {
                ids.insert(truckId)
            }
            // Also match by name in case ID format differs
            if let truckName = s.truck?.name, !truckName.isEmpty {
                ids.insert(truckName)
            }
        }
        return ids
    }

    /// Trucks already booked on the date of the schedule being assigned
    func trucksScheduledForSchedule(id: String) -> Set<String> {
        guard let schedule = allSchedules.first(where: { $0.id == id }) else { return [] }
        return trucksScheduledOn(date: schedule.dayKey)
    }

    init(config: AppConfiguration) {
        self.service = ScheduleService(baseURL: config.intelliShiftBaseURL)
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        // Load the month if we don't have data for it
        let newMonth = monthStringFor(date)
        Task { await loadSchedules(month: newMonth) }
    }

    func loadAllSchedules() async {
        // Load current month + next month for good coverage
        let currentMonth = monthStringFor(selectedDate)
        await loadSchedules(month: currentMonth)
    }

    func loadSchedules(month: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let m = month ?? monthStringFor(selectedDate)
        do {
            let fetched = try await service.fetchSchedules(month: m)
            // Merge: replace schedules for this month, keep others
            let prefix = m // "2026-04"
            allSchedules.removeAll { $0.dayKey.hasPrefix(prefix) }
            allSchedules.append(contentsOf: fetched)
            allSchedules.sort { $0.scheduledAt < $1.scheduledAt }
        } catch {
            errorMessage = error.localizedDescription
            print("[Schedule] Load error: \(error)")
        }
    }

    func createSchedule(
        scheduledAt: Date,
        type: String,
        mill: Mill?,
        yard: Yard?,
        truck: Vehicle?,
        distance: String?,
        duration: Double?,
        fuelCost: Double?,
        notes: String
    ) async -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let dateStr = formatter.string(from: scheduledAt)

        let payload = CreateSchedulePayload(
            scheduledAt: dateStr,
            type: type,
            mill: mill.map { ScheduleMill(name: $0.name, vendor: $0.vendor, city: $0.city, state: $0.state, uuid: $0.uuid) },
            yard: yard.map { ScheduleYard(posNumber: $0.posNumber, city: $0.city, state: $0.state, uuid: $0.uuid) },
            truck: truck.map { ScheduleTruck(id: String($0.id), name: $0.name, driver: $0.driver, operator: $0.`operator`) },
            distance: distance,
            duration: duration,
            fuelCost: fuelCost,
            notes: notes
        )

        do {
            _ = try await service.createSchedule(payload)
            await loadSchedules()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateStatus(id: String, status: String) async {
        do {
            try await service.updateSchedule(id: id, status: status)
            await loadSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignTruck(id: String, truck: ScheduleTruck) async {
        do {
            try await service.updateSchedule(id: id, truck: truck)
            await loadSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSchedule(id: String) async {
        do {
            try await service.deleteSchedule(id: id)
            await loadSchedules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func monthStringFor(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%d-%02d", c.year!, c.month!)
    }

    private func dayKeyFor(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
