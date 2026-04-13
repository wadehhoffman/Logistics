import SwiftUI

/// Bottom sheet showing every scheduled route for a given day, with inline
/// actions (mark status / assign truck / delete). Tap a row to open the
/// route detail for editing.
///
/// Phase iE — reuses ScheduleViewModel for data access. Phase iG will add
/// the HOS breakdown to the detail sheet itself.
struct DayDrawerView: View {
    let date: Date
    @Bindable var vm: ScheduleViewModel
    let onOpenRoute: (ScheduledRoute) -> Void
    let onAssignTruck: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: date)
    }

    private var dayRoutes: [ScheduledRoute] {
        vm.routes(on: date)
    }

    var body: some View {
        NavigationStack {
            Group {
                if dayRoutes.isEmpty {
                    ContentUnavailableView(
                        "No routes for this day",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Schedule a route from the Single Route tab to see it here.")
                    )
                } else {
                    List {
                        ForEach(dayRoutes) { route in
                            routeRow(route: route)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onOpenRoute(route)
                                    dismiss()
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task {
                                            await vm.deleteSchedule(id: route.id)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    if route.statusEnum == .scheduled {
                                        Button {
                                            Task { await vm.updateStatus(id: route.id, status: "delivered") }
                                        } label: {
                                            Label("Delivered", systemImage: "checkmark.circle")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func routeRow(route: ScheduledRoute) -> some View {
        let status = route.statusEnum
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(route.timeString).font(.headline)
                statusBadge(status)
                Spacer()
                if route.requiresOvernightRest { Text("🛌").font(.caption) }
                if route.hasHosViolations       { Text("⚠️").font(.caption) }
            }
            Text("\(route.mill?.name ?? "—") → \(route.yard?.posNumber ?? "—") \(route.yard?.city ?? "")")
                .font(.subheadline)
            HStack(spacing: 4) {
                Image(systemName: "truck.box.fill").imageScale(.small).foregroundStyle(.secondary)
                if let truck = route.truck {
                    let op = truck.operatorOrDriver
                    Text(op.isEmpty ? truck.name : "\(truck.name) – \(op)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Assign Truck") { onAssignTruck(route.id) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                }
                if let dist = route.distance {
                    Text("• \(dist)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ status: ScheduledRoute.Status) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch status {
            case .scheduled:             return ("scheduled",   Color.blue.opacity(0.15),   .blue)
            case .inProgress:            return ("in-progress", Color.orange.opacity(0.20), .orange)
            case .delivered, .completed: return ("delivered",   Color.green.opacity(0.15),  .green)
            case .cancelled:             return ("cancelled",   Color.gray.opacity(0.15),   .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }
}
