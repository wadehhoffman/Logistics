import SwiftUI

struct TruckPickerView: View {
    let vehicles: [Vehicle]
    let isLoading: Bool
    let onSelect: (Vehicle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredVehicles: [Vehicle] {
        guard !searchText.isEmpty else { return vehicles }
        let q = searchText.lowercased()
        return vehicles.filter {
            $0.name.lowercased().contains(q) ||
            $0.driver.lowercased().contains(q) ||
            $0.city.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading truck locations...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vehicles.isEmpty {
                    ContentUnavailableView(
                        "No Trucks Available",
                        systemImage: "truck.box",
                        description: Text("Could not load truck locations. Check IntelliShift configuration in Settings.")
                    )
                } else {
                    List {
                        // Status legend
                        HStack(spacing: 16) {
                            legendItem(color: .blue, label: "Moving")
                            legendItem(color: .orange, label: "Idle")
                            legendItem(color: .red, label: "Stopped")
                        }
                        .font(.caption)
                        .listRowBackground(Color.clear)

                        ForEach(filteredVehicles) { vehicle in
                            Button {
                                onSelect(vehicle)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(vehicle.status.color)
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(vehicle.name)
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text(vehicle.locationDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 8) {
                                            if !vehicle.driver.isEmpty {
                                                Label(vehicle.driver, systemImage: "person.fill")
                                            }
                                            if vehicle.speed > 0 {
                                                Label("\(Int(vehicle.speed)) mph", systemImage: "speedometer")
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    Text(vehicle.status.label)
                                        .font(.caption2).fontWeight(.bold)
                                        .foregroundStyle(vehicle.status.color)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search trucks...")
                }
            }
            .navigationTitle("Select Truck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
