import SwiftUI

struct ScheduleContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: ScheduleViewModel?
    @State private var showingCreateRoute = false

    var body: some View {
        if let viewModel {
            mainContent(vm: viewModel)
        } else {
            ProgressView("Loading...")
                .onAppear { viewModel = ScheduleViewModel(config: config) }
        }
    }

    @ViewBuilder
    private func mainContent(vm: ScheduleViewModel) -> some View {
        VStack(spacing: 0) {
            // Date picker centered at top
            DatePicker(
                "Date",
                selection: Binding(
                    get: { vm.selectedDate },
                    set: { vm.selectDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)

            // Day label
            Text(vm.selectedDateLabel)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.carterBlue)
                .padding(.bottom, 8)

            Divider()

            if vm.isLoading {
                Spacer()
                ProgressView("Loading schedules...")
                Spacer()
            } else if vm.filteredSchedules.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("No Routes Scheduled")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("for \(vm.selectedDateLabel)")
                        .font(.subheadline).foregroundStyle(.tertiary)

                    Button {
                        showingCreateRoute = true
                    } label: {
                        Label("Create a Route", systemImage: "plus.circle.fill")
                            .font(.subheadline).fontWeight(.semibold)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Color.carterBlue)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                Spacer()
            } else {
                // Route count
                Text("\(vm.filteredSchedules.count) route\(vm.filteredSchedules.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.top, 8)

                List {
                    ForEach(vm.filteredSchedules) { schedule in
                        ScheduleRowView(schedule: schedule, vm: vm)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await vm.loadAllSchedules() }
        .sheet(isPresented: $showingCreateRoute) {
            // Navigate user to Route Planner — just a hint for now
            NavigationStack {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.system(size: 48)).foregroundStyle(Color.carterBlue)
                    Text("Create a Route")
                        .font(.title3).fontWeight(.bold)
                    Text("Use the Route Planner or Truck Route from the main menu to calculate a route, then tap the Schedule button to add it here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding()
                .navigationTitle("New Route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingCreateRoute = false }
                    }
                }
            }
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRowView: View {
    let schedule: ScheduledRoute
    let vm: ScheduleViewModel
    @State private var showingAssignTruck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Time + status
            HStack {
                Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                Text(schedule.timeString).font(.subheadline).fontWeight(.semibold)
                Spacer()
                statusBadge(schedule.status)
            }

            // Mill → Yard
            HStack(spacing: 4) {
                Image(systemName: "building.2.fill").font(.caption2).foregroundStyle(.red)
                Text(schedule.mill?.name ?? "—").font(.caption).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.secondary)
                Image(systemName: "house.fill").font(.caption2).foregroundStyle(Color.carterBlue)
                Text(schedule.yard.map { "#\($0.posNumber ?? "") \($0.city ?? "")" } ?? "—")
                    .font(.caption).lineLimit(1)
            }

            // Truck + distance
            HStack {
                if let truck = schedule.truck {
                    HStack(spacing: 4) {
                        Image(systemName: "truck.box.fill").font(.caption2)
                        Text(truck.name).font(.caption2)
                        if let driver = truck.driver, !driver.isEmpty {
                            Text("(\(driver))").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.blue)
                } else if schedule.status == "scheduled" {
                    Button {
                        showingAssignTruck = true
                    } label: {
                        Label("Assign Truck", systemImage: "truck.box.fill")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange).cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let dist = schedule.distance {
                    Text(dist).font(.caption2).foregroundStyle(.secondary)
                }
            }

            // Notes
            if !schedule.notes.isEmpty {
                Text(schedule.notes)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 1)
            }

            // Actions
            if schedule.status == "scheduled" {
                HStack(spacing: 12) {
                    Button {
                        Task { await vm.updateStatus(id: schedule.id, status: "completed") }
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await vm.updateStatus(id: schedule.id, status: "cancelled") }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        Task { await vm.deleteSchedule(id: schedule.id) }
                    } label: {
                        Image(systemName: "trash").font(.caption2).foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingAssignTruck) {
            AssignTruckSheet(scheduleId: schedule.id, vm: vm, millName: schedule.mill?.name, yardPOS: schedule.yard?.posNumber)
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(
                status == "completed" ? Color.green.opacity(0.15) :
                status == "cancelled" ? Color.gray.opacity(0.15) :
                Color.blue.opacity(0.15)
            )
            .foregroundStyle(
                status == "completed" ? .green :
                status == "cancelled" ? .gray :
                .blue
            )
            .cornerRadius(4)
    }
}
