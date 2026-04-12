import SwiftUI
import CoreLocation

struct AssignTruckSheet: View {
    let scheduleId: String
    let vm: ScheduleViewModel
    let millName: String?
    let yardPOS: String?

    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @Environment(\.dismiss) private var dismiss
    @State private var vehicles: [Vehicle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var targetLat: Double?
    @State private var targetLon: Double?

    /// Truck IDs/names already booked on the same day as this schedule
    private var bookedTrucks: Set<String> {
        vm.trucksScheduledForSchedule(id: scheduleId)
    }

    private func isTruckBooked(_ vehicle: Vehicle) -> Bool {
        bookedTrucks.contains(String(vehicle.id)) || bookedTrucks.contains(vehicle.name)
    }

    private var sortedVehicles: [(vehicle: Vehicle, distance: Double?, booked: Bool)] {
        let filtered: [Vehicle]
        if searchText.isEmpty {
            filtered = vehicles
        } else {
            let q = searchText.lowercased()
            filtered = vehicles.filter {
                $0.name.lowercased().contains(q) ||
                $0.driver.lowercased().contains(q) ||
                $0.city.lowercased().contains(q)
            }
        }

        return filtered.map { v in
            var dist: Double? = nil
            if let lat = targetLat, let lon = targetLon, v.lat != 0, v.lon != 0 {
                let km = Haversine.distance(lat1: v.lat, lon1: v.lon, lat2: lat, lon2: lon)
                dist = km * 0.621371
            }
            return (v, dist, isTruckBooked(v))
        }.sorted { a, b in
            // Available trucks first, then by distance
            if a.booked != b.booked { return !a.booked }
            switch (a.distance, b.distance) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case let (ad?, bd?): return ad < bd
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading trucks...").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vehicles.isEmpty {
                    ContentUnavailableView("No Trucks", systemImage: "truck.box",
                        description: Text(errorMessage ?? "Could not load trucks"))
                } else {
                    List {
                        Section {
                            HStack(spacing: 16) {
                                legendDot(color: .blue, label: "Moving")
                                legendDot(color: .orange, label: "Idle")
                                legendDot(color: .red, label: "Stopped")
                            }
                            .font(.caption)
                        }

                        ForEach(sortedVehicles, id: \.vehicle.id) { item in
                            let booked = item.booked
                            Button {
                                guard !booked else { return }
                                Task {
                                    await vm.assignTruck(
                                        id: scheduleId,
                                        truck: ScheduleTruck(id: String(item.vehicle.id), name: item.vehicle.name, driver: item.vehicle.driver)
                                    )
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(booked ? Color.gray : item.vehicle.status.color)
                                        .frame(width: 10, height: 10)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.vehicle.name)
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundStyle(booked ? .secondary : .primary)
                                            if booked {
                                                Text("BOOKED")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                                    .background(Color.red.opacity(0.15))
                                                    .foregroundStyle(.red)
                                                    .cornerRadius(3)
                                            }
                                        }
                                        Text(item.vehicle.locationDescription)
                                            .font(.caption).foregroundStyle(.secondary)
                                        if !item.vehicle.driver.isEmpty {
                                            Text(item.vehicle.driver)
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        if let dist = item.distance {
                                            Text(String(format: "%.0f mi", dist))
                                                .font(.subheadline).fontWeight(.bold)
                                                .foregroundStyle(booked ? .secondary : Color.carterBlue)
                                        }
                                        Text(booked ? "Scheduled" : item.vehicle.status.label)
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(booked ? .red : item.vehicle.status.color)
                                    }
                                }
                                .opacity(booked ? 0.6 : 1.0)
                            }
                            .buttonStyle(.plain)
                            .disabled(booked)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search trucks...")
                }
            }
            .navigationTitle("Assign Truck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                resolveTargetCoordinates()
                await loadTrucks()
            }
        }
    }

    private func resolveTargetCoordinates() {
        if let pos = yardPOS {
            if let yard = locationStore.yards.first(where: { $0.posNumber == pos }) {
                targetLat = yard.lat
                targetLon = yard.lon
                return
            }
        }
        if let schedule = vm.allSchedules.first(where: { $0.id == scheduleId }),
           let yardCity = schedule.yard?.city,
           let yardState = schedule.yard?.state {
            if let yard = locationStore.yards.first(where: { $0.city == yardCity && $0.state == yardState }) {
                targetLat = yard.lat
                targetLon = yard.lon
            }
        }
    }

    private func loadTrucks() async {
        isLoading = true
        defer { isLoading = false }

        let service = IntelliShiftService(baseURL: config.intelliShiftBaseURL)
        do {
            vehicles = try await service.fetchVehicles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
