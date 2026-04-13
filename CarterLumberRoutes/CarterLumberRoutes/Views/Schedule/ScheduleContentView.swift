import SwiftUI

/// Calendar-first Schedule tab.
///
/// Vertical layout on iPhone:
///   ┌────────────────────────────────┐
///   │  ‹ April 2026 › [Today]        │   month nav
///   │                                │
///   │  Calendar grid                 │   monthly LazyVGrid
///   │  (day cells with line items)   │
///   │                                │
///   │  ── Next 7 Days ──             │   compact upcoming strip
///   │  • Mon Apr 14 (2) 06:00 …      │
///   │  • Tue Apr 15 …                │
///   └────────────────────────────────┘
///
/// Tap a day cell → DayDrawerView sheet.
/// Tap a line item → RouteDetailSheet (Phase iE uses a lightweight detail;
/// Phase iG expands it with full HOS breakdown + actions).
struct ScheduleContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: ScheduleViewModel?

    @State private var drawerDate: Date?
    @State private var detailRoute: ScheduledRoute?
    @State private var assignTruckScheduleId: String?

    var body: some View {
        Group {
            if let viewModel {
                mainContent(vm: viewModel)
            } else {
                ProgressView().onAppear { viewModel = ScheduleViewModel(config: config) }
            }
        }
    }

    @ViewBuilder
    private func mainContent(vm: ScheduleViewModel) -> some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: 16) {
                monthHeader(vm: vm)

                CalendarMonthView(
                    month: vm.currentMonth,
                    routesByDay: vm.routesByDay,
                    onOpenDay:   { date in drawerDate = date },
                    onOpenRoute: { route in detailRoute = route }
                )
                .padding(.horizontal, 4)

                next7DaysStrip(vm: vm)

                if let err = vm.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
            }
            .padding(.top, 8)
        }
        .overlay(alignment: .top) {
            if vm.isLoading && vm.allSchedules.isEmpty {
                ProgressView().padding(.top, 40)
            }
        }
        .task { await vm.loadAllSchedules() }
        .refreshable { await vm.loadAllSchedules() }
        .sheet(item: Binding(
            get: { drawerDate.map(DateWrapper.init) },
            set: { drawerDate = $0?.date }
        )) { wrapper in
            DayDrawerView(
                date: wrapper.date,
                vm: vm,
                onOpenRoute: { route in detailRoute = route },
                onAssignTruck: { id in assignTruckScheduleId = id }
            )
        }
        .sheet(item: $detailRoute) { route in
            RouteQuickDetailSheet(
                route: route,
                vm: vm,
                onAssignTruck: { id in
                    detailRoute = nil
                    assignTruckScheduleId = id
                }
            )
        }
        .sheet(item: Binding(
            get: { assignTruckScheduleId.map(StringId.init) },
            set: { assignTruckScheduleId = $0?.value }
        )) { wrapper in
            // Look up the current route so we know which mill/yard to sort by
            let route = vm.allSchedules.first { $0.id == wrapper.value }
            AssignTruckSheet(
                scheduleId: wrapper.value,
                vm: vm,
                millName: route?.mill?.name,
                yardPOS: route?.yard?.posNumber
            )
        }
    }

    // MARK: - Month header

    @ViewBuilder
    private func monthHeader(vm: ScheduleViewModel) -> some View {
        HStack {
            Button { vm.prevMonth() } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)

            Spacer()

            Text(vm.currentMonthLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.carterBlue)

            Spacer()

            Button { vm.nextMonth() } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)

            Button("Today") { vm.jumpToToday() }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    // MARK: - Next 7 days

    @ViewBuilder
    private func next7DaysStrip(vm: ScheduleViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT 7 DAYS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    dayStripRow(vm: vm, offset: offset)
                    if offset < 6 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func dayStripRow(vm: ScheduleViewModel, offset: Int) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today
        let routes = vm.routes(on: date)
        let isToday = offset == 0

        Button {
            drawerDate = date
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(date, format: .dateTime.weekday(.abbreviated))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Color.orange : .secondary)
                    Text(date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 52, alignment: .leading)

                if routes.isEmpty {
                    Text("No routes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(routes.prefix(2)) { route in
                            HStack(spacing: 4) {
                                Circle().fill(color(for: route.statusEnum)).frame(width: 6, height: 6)
                                Text(route.timeString).font(.caption).fontWeight(.medium)
                                Text(route.yard?.posNumber ?? "").font(.caption)
                                if let truckName = route.truck?.name {
                                    Text("• \(truckName)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        if routes.count > 2 {
                            Text("+\(routes.count - 2) more")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.carterBlue)
                        }
                    }
                    Spacer()
                    Text("\(routes.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.carterBlue)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.carterBlue.opacity(0.12)))
                }

                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func color(for status: ScheduledRoute.Status) -> Color {
        switch status {
        case .scheduled:             return .blue
        case .inProgress:            return .orange
        case .delivered, .completed: return .green
        case .cancelled:             return .red
        }
    }

    // MARK: - Sheet-item wrappers
    // SwiftUI's .sheet(item:) needs Identifiable; wrap Date / String.

    private struct DateWrapper: Identifiable {
        let date: Date
        var id: TimeInterval { date.timeIntervalSince1970 }
    }

    private struct StringId: Identifiable {
        let value: String
        var id: String { value }
    }
}

// MARK: - Quick detail sheet (Phase iE stub; Phase iG will add HOS breakdown)

/// Lightweight detail sheet for a scheduled route — shown when a calendar
/// line item is tapped. Kept separate from AssignTruckSheet so we can wire
/// the HOS breakdown in Phase iG without affecting the assign flow.
struct RouteQuickDetailSheet: View {
    let route: ScheduledRoute
    @Bindable var vm: ScheduleViewModel
    let onAssignTruck: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("When") {
                    LabeledContent("Date",  value: route.dateString)
                    LabeledContent("Time",  value: route.timeString)
                    LabeledContent("Status", value: route.status.capitalized)
                }

                Section("Route") {
                    LabeledContent("Mill", value: route.mill?.name ?? "—")
                    if let yard = route.yard {
                        LabeledContent("Yard", value: "\(yard.posNumber ?? "") \(yard.city ?? "")")
                    }
                    if let dist = route.distance { LabeledContent("Distance", value: dist) }
                }

                Section("Truck") {
                    if let truck = route.truck {
                        LabeledContent("Vehicle #", value: truck.name)
                        let op = truck.operatorOrDriver
                        if !op.isEmpty {
                            LabeledContent("Operator", value: op)
                        }
                    } else {
                        Button {
                            onAssignTruck(route.id)
                        } label: {
                            Label("Assign Truck", systemImage: "truck.box.fill")
                        }
                    }
                }

                if !route.notes.isEmpty {
                    Section("Notes") { Text(route.notes).font(.callout) }
                }

                if let hos = route.hosProjection, !hos.segments.isEmpty {
                    Section {
                        HOSBreakdownView(projection: hos)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Actions") {
                    if route.statusEnum == .scheduled {
                        Button {
                            Task {
                                await vm.updateStatus(id: route.id, status: "in-progress")
                                dismiss()
                            }
                        } label: { Label("Mark In-Progress", systemImage: "play.circle") }

                        Button {
                            Task {
                                await vm.updateStatus(id: route.id, status: "delivered")
                                dismiss()
                            }
                        } label: { Label("Mark Delivered", systemImage: "checkmark.circle") }
                            .foregroundStyle(.green)

                        Button(role: .destructive) {
                            Task {
                                await vm.updateStatus(id: route.id, status: "cancelled")
                                dismiss()
                            }
                        } label: { Label("Cancel Route", systemImage: "xmark.circle") }
                    } else if route.statusEnum == .inProgress {
                        Button {
                            Task {
                                await vm.updateStatus(id: route.id, status: "delivered")
                                dismiss()
                            }
                        } label: { Label("Mark Delivered", systemImage: "checkmark.circle") }
                            .foregroundStyle(.green)
                    }

                    Button(role: .destructive) {
                        Task {
                            await vm.deleteSchedule(id: route.id)
                            dismiss()
                        }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
