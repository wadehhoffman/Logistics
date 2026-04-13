import SwiftUI

/// Read-only Vehicles browser backed by IntelliShiftService. Mirrors the
/// web's Settings → Vehicles tab. Vehicles are the source of truth in
/// IntelliShift, so there's no create/edit/delete here — only view +
/// search + a "Show on map" action that jumps back to the Today tab
/// with the map zoomed onto the selected vehicle.
struct VehiclesSettingsView: View {
    @Environment(AppConfiguration.self) private var config

    @State private var vehicles: [Vehicle] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var filtered: [Vehicle] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = vehicles
        guard !q.isEmpty else { return all }
        return all.filter { v in
            v.name.lowercased().contains(q)
                || v.operatorOrDriver.lowercased().contains(q)
                || v.descriptionText.lowercased().contains(q)
                || v.city.lowercased().contains(q)
                || v.state.lowercased().contains(q)
                || v.type.rawValue.contains(q)
        }
    }

    private var sorted: [Vehicle] {
        filtered.sorted { a, b in
            if a.type != b.type { return a.type == .truck }
            return a.name < b.name
        }
    }

    var body: some View {
        List {
            Section {
                Text("Source: IntelliShift (read-only). Operator and vehicle assignments must be edited in IntelliShift.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if isLoading && vehicles.isEmpty {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if let err = errorMessage, vehicles.isEmpty {
                Section {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            } else {
                Section {
                    ForEach(sorted) { v in
                        vehicleRow(v)
                    }
                } header: {
                    Text("\(sorted.count) of \(vehicles.count)").font(.caption)
                }
            }
        }
        .navigationTitle("Vehicles")
        .searchable(text: $search, placement: .navigationBarDrawer, prompt: "Search by #, operator, description, city")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func vehicleRow(_ v: Vehicle) -> some View {
        HStack(spacing: 10) {
            typeBadge(v)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(v.name).font(.subheadline.weight(.semibold)).monospaced()
                    if !v.operatorOrDriver.isEmpty {
                        Text("– \(v.operatorOrDriver)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    statusDot(v.status)
                }
                if !v.descriptionText.isEmpty {
                    Text(v.descriptionText).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(.secondary)
                    Text(locationString(v)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !v.updated.isEmpty, let d = parseDate(v.updated) {
                        Text(d, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func typeBadge(_ v: Vehicle) -> some View {
        let color: Color = v.type == .truck ? .blue : v.type == .trailer ? .orange : .gray
        ZStack {
            RoundedRectangle(cornerRadius: v.type == .trailer ? 3 : 6)
                .fill(color.opacity(0.15))
                .frame(width: 34, height: 28)
            Image(systemName: v.type.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func statusDot(_ status: Vehicle.TruckStatus) -> some View {
        Circle().fill(status.color).frame(width: 8, height: 8)
    }

    private func locationString(_ v: Vehicle) -> String {
        let parts = [v.city, v.state].filter { !$0.isEmpty }
        return parts.isEmpty ? "Location unknown" : parts.joined(separator: ", ")
    }

    private func parseDate(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = DateFormatter()
        f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f2.date(from: s)
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let service = IntelliShiftService(baseURL: config.intelliShiftBaseURL)
            vehicles = try await service.fetchVehicles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
