import SwiftUI

/// Slide-up sheet shown when a vehicle cluster bubble is tapped.
/// Lists every vehicle at the clustered location. Tapping a row dismisses
/// the sheet and focuses the map on that vehicle.
struct ClusterDetailSheet: View {
    let vehicles: [Vehicle]
    let onSelect: (Vehicle) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sortedVehicles) { v in
                        Button {
                            onSelect(v)
                            dismiss()
                        } label: {
                            row(v)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("\(vehicles.count) vehicles at this location").font(.caption)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Vehicles here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sortedVehicles: [Vehicle] {
        vehicles.sorted { a, b in
            if a.type != b.type { return a.type == .truck }
            return a.name < b.name
        }
    }

    @ViewBuilder
    private func row(_ v: Vehicle) -> some View {
        HStack(spacing: 10) {
            typeBadge(v)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(v.name).font(.subheadline.weight(.semibold)).monospaced()
                    if !v.operatorOrDriver.isEmpty {
                        Text("– \(v.operatorOrDriver)").font(.caption)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    statusDot(v.status)
                }
                Text(locationString(v)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
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
}
