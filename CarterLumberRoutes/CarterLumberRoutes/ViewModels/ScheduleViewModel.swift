import Foundation
import SwiftUI

@MainActor @Observable
final class ScheduleViewModel {
    var schedules: [ScheduledRoute] = []
    var selectedDay: String?  // "2026-04-15"
    var currentYear: Int
    var currentMonth: Int     // 0-indexed
    var isLoading = false
    var errorMessage: String?
    var showListView = true   // true = list, false = calendar

    private let service: ScheduleService

    var monthString: String {
        String(format: "%d-%02d", currentYear, currentMonth + 1)
    }

    var monthLabel: String {
        let names = ["January","February","March","April","May","June","July","August","September","October","November","December"]
        return "\(names[currentMonth]) \(currentYear)"
    }

    var selectedDaySchedules: [ScheduledRoute] {
        guard let day = selectedDay else { return [] }
        return schedules.filter { $0.dayKey == day }
    }

    /// Group schedules by day for calendar dots
    var scheduleDays: Set<String> {
        Set(schedules.map(\.dayKey))
    }

    init(config: AppConfiguration) {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        self.currentYear = now.year ?? 2026
        self.currentMonth = (now.month ?? 4) - 1
        self.service = ScheduleService(baseURL: config.intelliShiftBaseURL)
    }

    func loadSchedules() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            schedules = try await service.fetchSchedules(month: monthString)
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
            mill: mill.map { ScheduleMill(name: $0.name, vendor: $0.vendor, city: $0.city, state: $0.state) },
            yard: yard.map { ScheduleYard(posNumber: $0.posNumber, city: $0.city, state: $0.state) },
            truck: truck.map { ScheduleTruck(id: String($0.id), name: $0.name, driver: $0.driver) },
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

    func prevMonth() {
        currentMonth -= 1
        if currentMonth < 0 { currentMonth = 11; currentYear -= 1 }
        Task { await loadSchedules() }
    }

    func nextMonth() {
        currentMonth += 1
        if currentMonth > 11 { currentMonth = 0; currentYear += 1 }
        Task { await loadSchedules() }
    }
}
