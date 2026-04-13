import SwiftUI

/// Today dispatcher dashboard — replaces the old "Route Truck" tab.
///
/// Vertical layout on iPhone:
///   ┌───────────────────────────┐
///   │  Map (routes + vehicles)  │   ≈ 40% of screen
///   ├───────────────────────────┤
///   │  Date stepper             │
///   │  Routes list              │
///   │  Vehicles list            │   scroll
///   └───────────────────────────┘
///
/// Auto-refreshes vehicles every 60 seconds while onscreen. Date changes
/// reload routes immediately.
struct TodayView: View {
    @Environment(AppConfiguration.self) private var config
    @State private var viewModel: TodayViewModel?

    @State private var focusRouteId: String? = nil
    @State private var focusVehicleId: Int? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView().onAppear { viewModel = TodayViewModel(config: config) }
            }
        }
    }

    @ViewBuilder
    private func content(vm: TodayViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            // Map: fixed height, takes the top portion
            TodayMapView(
                routes: vm.sortedRoutes,
                vehicles: vm.vehicles,
                focusRouteId: $focusRouteId,
                focusVehicleId: $focusVehicleId
            )
            .frame(height: 280)
            .clipped()

            Divider()

            // Scrollable list
            List {
                dateSection(vm: vm)
                routesSection(vm: vm)
                vehiclesSection(vm: vm)
            }
            .listStyle(.insetGrouped)
        }
        .task {
            await vm.loadAll()
            vm.startAutoRefresh()
        }
        .onDisappear { vm.stopAutoRefresh() }
        .refreshable { await vm.loadAll() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func dateSection(vm: TodayViewModel) -> some View {
        Section {
            HStack(spacing: 10) {
                Button { vm.stepDay(by: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)

                DatePicker("", selection: Binding(
                    get: { vm.selectedDate },
                    set: { vm.selectedDate = $0; Task { await vm.loadRoutes() } }
                ), displayedComponents: .date)
                .labelsHidden()

                Button { vm.stepDay(by: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)

                if !vm.isSelectedDateToday {
                    Button("Today") { vm.jumpToToday() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            HStack {
                Text(vm.selectedDateLabel)
                Spacer()
                Button {
                    Task { await vm.loadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func routesSection(vm: TodayViewModel) -> some View {
        Section("Routes (\(vm.sortedRoutes.count))") {
            if vm.isLoadingRoutes && vm.sortedRoutes.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if vm.sortedRoutes.isEmpty {
                Text("No routes scheduled for this day.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(vm.sortedRoutes) { route in
                    routeRow(route: route)
                        .contentShape(Rectangle())
                        .onTapGesture { focusRouteId = route.id }
                }
            }
        }
    }

    @ViewBuilder
    private func vehiclesSection(vm: TodayViewModel) -> some View {
        Section {
            TextField("Filter by #, operator, city, state…", text: Binding(
                get: { vm.vehicleFilter },
                set: { vm.vehicleFilter = $0 }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if vm.isLoadingVehicles && vm.vehicles.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if vm.filteredVehicles.isEmpty {
                Text(vm.vehicles.isEmpty ? "No vehicles available." : "No vehicles match.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(vm.filteredVehicles) { vehicle in
                    vehicleRow(vehicle: vehicle)
                        .contentShape(Rectangle())
                        .onTapGesture { focusVehicleId = vehicle.id }
                }
            }
        } header: {
            HStack {
                Text("Vehicles")
                Spacer()
                Text("\(vm.truckCount) trucks • \(vm.trailerCount) trailers")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } footer: {
            Text("Positions refresh automatically every 60 seconds.")
                .font(.caption2)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func routeRow(route: ScheduledRoute) -> some View {
        let status = route.statusEnum
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(route.timeString).font(.subheadline.weight(.semibold))
                statusBadge(status)
                Spacer()
                if route.requiresOvernightRest { Text("🛌").font(.caption) }
                if route.hasHosViolations { Text("⚠️").font(.caption) }
            }
            Text("\(route.mill?.name ?? "?") → \(route.yard?.posNumber ?? "?") \(route.yard?.city ?? "")")
                .font(.callout)
            HStack(spacing: 4) {
                Image(systemName: "truck.box.fill").imageScale(.small).foregroundStyle(.secondary)
                Text(route.truck.map { $0.operatorOrDriver.isEmpty ? $0.name : "\($0.name) – \($0.operatorOrDriver)" } ?? "No truck assigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let dist = route.distance {
                    Text("• \(dist)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func vehicleRow(vehicle: Vehicle) -> some View {
        HStack(spacing: 10) {
            vehicleTypeBadge(vehicle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(vehicle.name).font(.subheadline.weight(.semibold))
                    if !vehicle.operatorOrDriver.isEmpty {
                        Text("– \(vehicle.operatorOrDriver)").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusDot(vehicle.status)
                }
                Text([vehicle.city, vehicle.state].filter { !$0.isEmpty }.joined(separator: ", ").isEmpty
                     ? "Location unknown"
                     : [vehicle.city, vehicle.state].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bits

    @ViewBuilder
    private func statusBadge(_ status: ScheduledRoute.Status) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch status {
            case .scheduled:  return ("scheduled", Color.blue.opacity(0.15),   .blue)
            case .inProgress: return ("in-progress", Color.orange.opacity(0.2), .orange)
            case .delivered, .completed: return ("delivered", Color.green.opacity(0.15), .green)
            case .cancelled:  return ("cancelled", Color.gray.opacity(0.15),   .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }

    @ViewBuilder
    private func statusDot(_ status: Vehicle.TruckStatus) -> some View {
        Circle().fill(status.color).frame(width: 8, height: 8)
    }

    @ViewBuilder
    private func vehicleTypeBadge(_ vehicle: Vehicle) -> some View {
        let color: Color = vehicle.type == .truck ? .blue : vehicle.type == .trailer ? .orange : .gray
        ZStack {
            RoundedRectangle(cornerRadius: vehicle.type == .trailer ? 3 : 6)
                .fill(color.opacity(0.15))
                .frame(width: 28, height: 22)
            Image(systemName: vehicle.type.systemImage)
                .font(.caption)
                .foregroundStyle(color)
        }
    }
}
