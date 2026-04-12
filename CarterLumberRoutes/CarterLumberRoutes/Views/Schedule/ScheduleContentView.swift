import SwiftUI

struct ScheduleContentView: View {
    @Environment(AppConfiguration.self) private var config
    @State private var viewModel: ScheduleViewModel?

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
            // View toggle
            HStack {
                Text("SCHEDULED ROUTES").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                Spacer()
                Picker("View", selection: Binding(
                    get: { vm.showListView },
                    set: { vm.showListView = $0 }
                )) {
                    Text("List").tag(true)
                    Text("Calendar").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 8)

            if vm.isLoading {
                Spacer()
                ProgressView("Loading schedules...")
                Spacer()
            } else if vm.showListView {
                ScheduleListView(vm: vm)
            } else {
                ScheduleCalendarView(vm: vm)
            }
        }
        .task { await vm.loadSchedules() }
    }
}

// MARK: - List View

struct ScheduleListView: View {
    let vm: ScheduleViewModel

    var body: some View {
        if vm.schedules.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40)).foregroundStyle(.secondary)
                Text("No scheduled routes")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Calculate a route and tap Schedule")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        } else {
            List {
                ForEach(vm.schedules) { schedule in
                    ScheduleRowView(schedule: schedule, vm: vm)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct ScheduleRowView: View {
    let schedule: ScheduledRoute
    let vm: ScheduleViewModel
    @State private var showingAssignTruck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date + status
            HStack {
                Text(schedule.dateString).font(.caption).fontWeight(.semibold)
                Text(schedule.timeString).font(.caption).foregroundStyle(.secondary)
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
                    Label(truck.name, systemImage: "truck.box.fill")
                        .font(.caption2).foregroundStyle(.blue)
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

            // Actions
            if schedule.status == "scheduled" {
                HStack(spacing: 8) {
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
                            .font(.caption2).foregroundStyle(.red)
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
            AssignTruckSheet(scheduleId: schedule.id, vm: vm, yardLat: nil, yardLon: nil)
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

// MARK: - Calendar View

struct ScheduleCalendarView: View {
    let vm: ScheduleViewModel
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(spacing: 8) {
            // Month nav
            HStack {
                Button { vm.prevMonth() } label: {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                }
                Spacer()
                Text(vm.monthLabel).font(.headline).fontWeight(.bold).foregroundStyle(Color.carterBlue)
                Spacer()
                Button { vm.nextMonth() } label: {
                    Image(systemName: "chevron.right").fontWeight(.semibold)
                }
            }
            .padding(.horizontal)

            // Weekday headers
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day).font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Days grid
            let days = calendarDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    if day.isEmpty {
                        Text("").frame(height: 40)
                    } else {
                        let dateStr = String(format: "%d-%02d-%02d", vm.currentYear, vm.currentMonth + 1, Int(day)!)
                        let hasRoutes = vm.scheduleDays.contains(dateStr)
                        let isSelected = vm.selectedDay == dateStr
                        let isToday = dateStr == todayString()

                        Button {
                            vm.selectedDay = dateStr
                        } label: {
                            VStack(spacing: 2) {
                                Text(day)
                                    .font(.subheadline)
                                    .fontWeight(isToday ? .bold : .regular)
                                    .foregroundStyle(isSelected ? .white : isToday ? Color.carterBlue : .primary)
                                Circle()
                                    .fill(hasRoutes ? Color.orange : Color.clear)
                                    .frame(width: 6, height: 6)
                            }
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.carterBlue : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)

            // Selected day routes
            if let _ = vm.selectedDay {
                Divider().padding(.horizontal)
                if vm.selectedDaySchedules.isEmpty {
                    Text("No routes on this day")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(vm.selectedDaySchedules) { schedule in
                                ScheduleRowView(schedule: schedule, vm: vm)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    private func calendarDays() -> [String] {
        let firstDay = Calendar.current.component(.weekday, from:
            Calendar.current.date(from: DateComponents(year: vm.currentYear, month: vm.currentMonth + 1, day: 1))!
        ) - 1  // 0=Sunday
        let daysInMonth = Calendar.current.range(of: .day, in: .month,
            for: Calendar.current.date(from: DateComponents(year: vm.currentYear, month: vm.currentMonth + 1))!
        )!.count

        var days: [String] = Array(repeating: "", count: firstDay)
        for d in 1...daysInMonth { days.append(String(d)) }
        return days
    }

    private func todayString() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
