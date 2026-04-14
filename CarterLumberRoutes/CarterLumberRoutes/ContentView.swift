import SwiftUI

struct ContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var selectedPage: AppPage = .singleRoute
    @State private var showMenu = false

    enum AppPage: String, CaseIterable, Identifiable {
        case singleRoute = "Route Planner"
        case today = "Today"
        case schedule = "Schedule"
        case drivers = "Drivers"
        case settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .singleRoute: return "arrow.triangle.turn.up.right.diamond"
            case .today:       return "map.fill"
            case .schedule:    return "calendar"
            case .drivers:     return "person.2.fill"
            case .settings:    return "gear"
            }
        }
        var subtitle: String {
            switch self {
            case .singleRoute: return "Mill to Yard routing"
            case .today:       return "Dispatcher dashboard"
            case .schedule:    return "View & manage scheduled routes"
            case .drivers:     return "HOS tracking & compliance"
            case .settings:    return "Server, fuel, reference data"
            }
        }
    }

    var body: some View {
        ZStack {
            mainContent.disabled(showMenu)
            if showMenu {
                Color.black.opacity(0.4).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { showMenu = false } }
                    .transition(.opacity)
            }
            sideMenu
        }
        .animation(.easeOut(duration: 0.25), value: showMenu)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedPage {
        case .singleRoute:
            SingleRouteContentView(showMenu: $showMenu)
        case .today:
            NavigationStack {
                TodayView()
                    .navigationTitle("Today")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                                Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                            }
                        }
                    }
            }
        case .schedule:
            NavigationStack {
                ScheduleContentView()
                    .navigationTitle("Schedule")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                                Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                            }
                        }
                    }
            }
        case .drivers:
            NavigationStack {
                DriversView()
                    .navigationTitle("Drivers")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                                Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                            }
                        }
                    }
            }
        case .settings:
            NavigationStack {
                SettingsContentView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                                Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                            }
                        }
                    }
            }
        }
    }

    private var sideMenu: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "building.2.fill").font(.system(size: 32)).foregroundStyle(.white)
                    Text("Carter Lumber").font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    Text("Route Planner").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24).padding(.top, 20)
                .background(LinearGradient(colors: [Color.carterDarkBlue, Color.carterBlue], startPoint: .topLeading, endPoint: .bottomTrailing))

                VStack(spacing: 4) { ForEach(AppPage.allCases) { page in menuItem(page: page) } }
                    .padding(.top, 12).padding(.horizontal, 12)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("\(locationStore.mills.count) mills / \(locationStore.yards.count) yards").font(.caption2).foregroundStyle(.tertiary)
                    Text("v1.0.0").font(.caption2).foregroundStyle(.quaternary)
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity).background(Color(.systemBackground))
            .offset(x: showMenu ? 0 : -UIScreen.main.bounds.width)
            Spacer(minLength: 0)
        }.ignoresSafeArea()
    }

    private func menuItem(page: AppPage) -> some View {
        Button {
            selectedPage = page
            withAnimation(.easeOut(duration: 0.25)) { showMenu = false }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: page.icon).font(.title3).frame(width: 28)
                    .foregroundStyle(selectedPage == page ? .white : Color.carterBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.rawValue).font(.body).fontWeight(.semibold)
                        .foregroundStyle(selectedPage == page ? .white : .primary)
                    Text(page.subtitle).font(.caption)
                        .foregroundStyle(selectedPage == page ? .white.opacity(0.8) : .secondary)
                }
                Spacer()
                if selectedPage == page {
                    Image(systemName: "checkmark").font(.caption).fontWeight(.bold).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(selectedPage == page ? Color.carterBlue : Color.clear).cornerRadius(12)
        }.buttonStyle(.plain)
    }
}

// MARK: - Floating hamburger button overlay

struct FloatingMenuButton: View {
    @Binding var showMenu: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { showMenu = true }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.35))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
    }
}

// MARK: - Single Route

struct SingleRouteContentView: View {
    @Binding var showMenu: Bool
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: SingleRouteViewModel?
    @State private var mapViewModel = MapViewModel()
    @State private var showingMillPicker = false
    @State private var showingYardPicker = false
    @State private var showingKPICard = false
    @State private var showingScheduleSheet = false
    @State private var scheduleVM: ScheduleViewModel?

    var body: some View {
        if let viewModel {
            mainContent(vm: viewModel)
        } else {
            ProgressView("Loading...")
                .onAppear { viewModel = SingleRouteViewModel(config: config) }
        }
    }

    @ViewBuilder
    private func mainContent(vm: SingleRouteViewModel) -> some View {
        ZStack {
            if vm.routeResult != nil {
                fullScreenMapView(vm: vm)
            } else {
                pickerModeView(vm: vm)
            }
        }
        .sheet(isPresented: $showingMillPicker) {
            MillPickerView(mills: locationStore.mills) { mill in Task { await vm.selectMill(mill) } }
        }
        .sheet(isPresented: $showingYardPicker) {
            YardPickerView(yards: locationStore.yards) { yard in vm.selectedYard = yard }
        }
        .fullScreenCover(isPresented: $showingKPICard) {
            if let vm = viewModel {
                RouteKPICardView(vm: vm, mapViewModel: mapViewModel) { showingKPICard = false }
            }
        }
        .sheet(isPresented: $showingScheduleSheet) {
            if let vm = viewModel {
                ScheduleRouteSheet(
                    routeType: "single",
                    mill: vm.selectedMill,
                    yard: vm.selectedYard,
                    truck: nil,
                    distance: vm.routeResult?.formattedDistance,
                    duration: vm.routeResult?.duration,
                    fuelCost: vm.fuelEstimate?.totalCost,
                    vm: scheduleVM ?? ScheduleViewModel(config: config),
                    onDone: { }
                )
            }
        }
        .onAppear {
            if scheduleVM == nil { scheduleVM = ScheduleViewModel(config: config) }
        }
    }

    @ViewBuilder
    private func fullScreenMapView(vm: SingleRouteViewModel) -> some View {
        MapContainerView(
            routeCoordinates: mapViewModel.routeCoordinates,
            annotations: mapViewModel.allAnnotations,
            isFallbackRoute: mapViewModel.isFallbackRoute,
            showTrafficLayer: mapViewModel.showTrafficLayer
        )
        .ignoresSafeArea()

        // Top-left: hamburger
        VStack {
            HStack {
                FloatingMenuButton(showMenu: $showMenu)
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 4)

            Spacer()

            // Bottom bar: distance left, buttons right
            HStack(alignment: .bottom) {
                // Bottom-left: distance label
                if let route = vm.routeResult {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.formattedDistance)
                            .font(.system(size: 28, weight: .heavy))
                        Text(route.formattedDuration)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                }

                Spacer()

                // Bottom-right: action buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            vm.clearRoute(); mapViewModel.clearRoute()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }

                    Button { showingScheduleSheet = true } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }

                    Button { showingKPICard = true } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.carterBlue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
    }

    @ViewBuilder
    private func pickerModeView(vm: SingleRouteViewModel) -> some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    MapContainerView(
                        routeCoordinates: mapViewModel.routeCoordinates,
                        annotations: mapViewModel.allAnnotations,
                        isFallbackRoute: mapViewModel.isFallbackRoute,
                        showTrafficLayer: mapViewModel.showTrafficLayer
                    )
                    .frame(height: geo.size.height * 0.5)

                    Divider()

                    ScrollView {
                        VStack(spacing: 12) {
                            if let error = vm.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                                    .padding(10).frame(maxWidth: .infinity)
                                    .background(Color.red.opacity(0.1)).cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("MILL / SUPPLIER").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Button { showingMillPicker = true } label: {
                                    HStack {
                                        Text(vm.selectedMill?.shortName ?? "Select a mill or supplier")
                                            .foregroundStyle(vm.selectedMill != nil ? .primary : .secondary)
                                        Spacer()
                                        if vm.isGeocodingMill { ProgressView().controlSize(.small) }
                                        else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    }
                                    .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                                }.buttonStyle(.plain)
                                if let mill = vm.selectedMill {
                                    Text(mill.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("YARD").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Button { showingYardPicker = true } label: {
                                    HStack {
                                        Text(vm.selectedYard?.displayName ?? "Select a yard")
                                            .foregroundStyle(vm.selectedYard != nil ? .primary : .secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                    .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                                }.buttonStyle(.plain)
                                if let yard = vm.selectedYard {
                                    Text("\(yard.fullAddress) — \(yard.manager)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                Task {
                                    await vm.calculateRoute()
                                    if let result = vm.routeResult, let mill = vm.selectedMill,
                                       let coord = vm.millCoordinate, let yard = vm.selectedYard {
                                        mapViewModel.setRoute(result: result, mill: mill, millCoord: coord, yard: yard)
                                    }
                                }
                            } label: {
                                HStack {
                                    if vm.isCalculating { ProgressView().controlSize(.small).tint(.white) }
                                    Text(vm.isCalculating ? "Calculating..." : "Get Route & Distance").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(vm.canCalculate ? Color.carterBlue : Color.gray)
                                .foregroundStyle(.white).cornerRadius(8)
                            }.disabled(!vm.canCalculate)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Route Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                        Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                    }
                }
            }
        }
    }
}

// MARK: - Route KPI Full Screen Card

struct RouteKPICardView: View {
    let vm: SingleRouteViewModel
    let mapViewModel: MapViewModel
    let onDismiss: () -> Void

    @Environment(AppConfiguration.self) private var config
    @State private var showingScheduleSheet = false
    @State private var showingTruckRoute = false
    @State private var scheduleVM: ScheduleViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let mill = vm.selectedMill, let yard = vm.selectedYard {
                        HStack(spacing: 8) {
                            Image(systemName: "building.2.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mill.name).font(.subheadline).fontWeight(.semibold)
                                Text("\(mill.city), \(mill.state)").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.down").foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "house.fill").foregroundStyle(Color.carterBlue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(yard.displayName).font(.subheadline).fontWeight(.semibold)
                                Text(yard.fullAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Action buttons: Schedule + Route Truck
                    HStack(spacing: 10) {
                        Button { showingScheduleSheet = true } label: {
                            Label("Schedule", systemImage: "calendar.badge.plus")
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Color.orange).foregroundStyle(.white).cornerRadius(8)
                        }.buttonStyle(.plain)

                        Button { showingTruckRoute = true } label: {
                            Label("Route Truck", systemImage: "truck.box.fill")
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Color.carterBlue).foregroundStyle(.white).cornerRadius(8)
                        }.buttonStyle(.plain)
                    }

                    if let route = vm.routeResult { RouteSummaryCard(route: route) }
                    if let fuel = vm.fuelEstimate { FuelEstimateCard(estimate: fuel) }
                    if !vm.weatherPoints.isEmpty {
                        WeatherAlongRouteCard(points: vm.weatherPoints)
                    } else if vm.isFetchingWeather {
                        ProgressView("Fetching weather...").padding()
                    }

                    Button {
                        vm.clearRoute(); mapViewModel.clearRoute(); onDismiss()
                    } label: {
                        Label("New Route", systemImage: "arrow.counterclockwise")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color(.systemGray5)).cornerRadius(8)
                    }.buttonStyle(.plain).padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Route Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingScheduleSheet) {
                ScheduleRouteSheet(
                    routeType: "single",
                    mill: vm.selectedMill,
                    yard: vm.selectedYard,
                    truck: nil,
                    distance: vm.routeResult?.formattedDistance,
                    duration: vm.routeResult?.duration,
                    fuelCost: vm.fuelEstimate?.totalCost,
                    vm: scheduleVM ?? ScheduleViewModel(config: config),
                    onDone: { }
                )
            }
            .sheet(isPresented: $showingTruckRoute) {
                TruckAssignFromRouteSheet(mill: vm.selectedMill, yard: vm.selectedYard, config: config)
            }
            .onAppear {
                if scheduleVM == nil { scheduleVM = ScheduleViewModel(config: config) }
            }
        }
    }
}

/// Sheet to pick a truck for routing from the Route Details card
struct TruckAssignFromRouteSheet: View {
    let mill: Mill?
    let yard: Yard?
    let config: AppConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var vehicles: [Vehicle] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading trucks...").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vehicles.isEmpty {
                    ContentUnavailableView("No Trucks", systemImage: "truck.box",
                        description: Text("Could not load truck locations"))
                } else {
                    List {
                        Section {
                            Text("Select a truck to route to \(mill?.name ?? "mill") then to \(yard?.displayName ?? "yard")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(vehicles) { v in
                            HStack(spacing: 12) {
                                Circle().fill(v.status.color).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name).font(.subheadline).fontWeight(.semibold)
                                    Text(v.locationDescription).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(v.status.label).font(.caption2).fontWeight(.semibold)
                                    .foregroundStyle(v.status.color)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Route Truck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                let service = IntelliShiftService(baseURL: config.intelliShiftBaseURL)
                do { vehicles = try await service.fetchVehicles() } catch {}
                isLoading = false
            }
        }
    }
}

// MARK: - Truck Route

struct TruckRouteContentView: View {
    @Binding var showMenu: Bool
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: TruckRouteViewModel?
    @State private var mapViewModel = MapViewModel()
    @State private var showingTruckPicker = false
    @State private var showingMillPicker = false
    @State private var showingYardPicker = false
    @State private var showingKPICard = false
    @State private var showingScheduleSheet = false
    @State private var scheduleVM: ScheduleViewModel?

    var body: some View {
        if let viewModel {
            mainContent(vm: viewModel)
        } else {
            ProgressView("Loading...")
                .onAppear { viewModel = TruckRouteViewModel(config: config) }
        }
    }

    @ViewBuilder
    private func mainContent(vm: TruckRouteViewModel) -> some View {
        ZStack {
            if vm.twoLegRoute != nil {
                fullScreenMapView(vm: vm)
            } else {
                pickerModeView(vm: vm)
            }
        }
        .sheet(isPresented: $showingTruckPicker) {
            TruckPickerView(viewModel: vm) { truck in vm.selectedVehicle = truck }
        }
        .sheet(isPresented: $showingMillPicker) {
            MillPickerView(mills: locationStore.mills) { mill in Task { await vm.selectMill(mill) } }
        }
        .sheet(isPresented: $showingYardPicker) {
            YardPickerView(yards: locationStore.yards) { yard in vm.selectedYard = yard }
        }
        .fullScreenCover(isPresented: $showingKPICard) {
            if let vm = viewModel {
                TruckKPICardView(vm: vm, mapViewModel: mapViewModel) { showingKPICard = false }
            }
        }
        .sheet(isPresented: $showingScheduleSheet) {
            if let vm = viewModel {
                ScheduleRouteSheet(
                    routeType: "truck",
                    mill: vm.selectedMill,
                    yard: vm.selectedYard,
                    truck: vm.selectedVehicle,
                    distance: vm.twoLegRoute?.formattedTotalDistance,
                    duration: vm.twoLegRoute?.totalDuration,
                    fuelCost: vm.fuelEstimate?.totalCost,
                    vm: scheduleVM ?? ScheduleViewModel(config: config),
                    onDone: { }
                )
            }
        }
        .onAppear {
            if scheduleVM == nil { scheduleVM = ScheduleViewModel(config: config) }
        }
    }

    @ViewBuilder
    private func fullScreenMapView(vm: TruckRouteViewModel) -> some View {
        MapContainerView(
            routeCoordinates: mapViewModel.routeCoordinates,
            annotations: mapViewModel.allAnnotations,
            isFallbackRoute: mapViewModel.isFallbackRoute,
            showTrafficLayer: mapViewModel.showTrafficLayer
        )
        .ignoresSafeArea()

        VStack {
            HStack {
                FloatingMenuButton(showMenu: $showMenu)
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 4)

            Spacer()

            HStack(alignment: .bottom) {
                // Bottom-left: distance label
                if let route = vm.twoLegRoute {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.formattedTotalDistance)
                            .font(.system(size: 28, weight: .heavy))
                        Text(route.formattedTotalDuration)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
                }

                Spacer()

                // Bottom-right: action buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            vm.clearRoute(); mapViewModel.clearRoute()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial).background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }

                    Button { showingScheduleSheet = true } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.orange)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }

                    Button { showingKPICard = true } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.carterBlue).clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
    }

    @ViewBuilder
    private func pickerModeView(vm: TruckRouteViewModel) -> some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    MapContainerView(
                        routeCoordinates: mapViewModel.routeCoordinates,
                        annotations: mapViewModel.allAnnotations,
                        isFallbackRoute: mapViewModel.isFallbackRoute,
                        showTrafficLayer: mapViewModel.showTrafficLayer
                    )
                    .frame(height: geo.size.height * 0.5)

                    Divider()

                    ScrollView {
                        VStack(spacing: 12) {
                            if let error = vm.errorMessage {
                                Text(error).font(.caption).foregroundStyle(.red)
                                    .padding(10).background(Color.red.opacity(0.1)).cornerRadius(6)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("1. SELECT TRUCK").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Button { showingTruckPicker = true } label: {
                                    HStack {
                                        if let truck = vm.selectedVehicle {
                                            Circle().fill(truck.status.color).frame(width: 10, height: 10)
                                            Text(truck.name)
                                        } else { Text("Select a truck").foregroundStyle(.secondary) }
                                        Spacer()
                                        if vm.isLoadingTrucks { ProgressView().controlSize(.small) }
                                        else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    }
                                    .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                                }.buttonStyle(.plain)
                                if let truck = vm.selectedVehicle {
                                    Text("\(truck.locationDescription) — \(truck.status.label)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("2. SELECT MILL / SUPPLIER").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Button { showingMillPicker = true } label: {
                                    HStack {
                                        Text(vm.selectedMill?.shortName ?? "Select a mill")
                                            .foregroundStyle(vm.selectedMill != nil ? .primary : .secondary)
                                        Spacer()
                                        if vm.isGeocodingMill { ProgressView().controlSize(.small) }
                                        else { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    }
                                    .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("3. SELECT YARD").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Button { showingYardPicker = true } label: {
                                    HStack {
                                        Text(vm.selectedYard?.displayName ?? "Select a yard")
                                            .foregroundStyle(vm.selectedYard != nil ? .primary : .secondary)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                    .padding(12).background(Color(.systemGray6)).cornerRadius(8)
                                }.buttonStyle(.plain)
                            }

                            Button {
                                Task {
                                    await vm.calculateTruckRoute()
                                    if let route = vm.twoLegRoute,
                                       let truck = vm.selectedVehicle,
                                       let mill = vm.selectedMill,
                                       let millCoord = vm.millCoordinate,
                                       let yard = vm.selectedYard {
                                        mapViewModel.setTruckRoute(
                                            geometry: route.combinedGeometry,
                                            vehicle: truck, mill: mill, millCoord: millCoord, yard: yard
                                        )
                                    }
                                }
                            } label: {
                                HStack {
                                    if vm.isCalculating { ProgressView().controlSize(.small).tint(.white) }
                                    Text(vm.isCalculating ? "Calculating..." : "Calculate Truck Route").fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity).padding(14)
                                .background(vm.canCalculate ? Color.carterBlue : .gray)
                                .foregroundStyle(.white).cornerRadius(8)
                            }.disabled(!vm.canCalculate)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Truck Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation(.easeOut(duration: 0.25)) { showMenu = true } } label: {
                        Image(systemName: "line.3.horizontal").font(.title3).foregroundStyle(Color.carterBlue)
                    }
                }
            }
        }
    }
}

// MARK: - Truck KPI Full Screen Card

struct TruckKPICardView: View {
    let vm: TruckRouteViewModel
    let mapViewModel: MapViewModel
    let onDismiss: () -> Void

    @Environment(AppConfiguration.self) private var config
    @State private var showingScheduleSheet = false
    @State private var scheduleVM: ScheduleViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let truck = vm.selectedVehicle, let mill = vm.selectedMill, let yard = vm.selectedYard {
                        HStack(spacing: 8) {
                            Image(systemName: "truck.box.fill").foregroundStyle(truck.status.color)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(truck.name).font(.subheadline).fontWeight(.semibold)
                                Text(truck.locationDescription).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.down").foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "building.2.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mill.name).font(.subheadline).fontWeight(.semibold)
                                Text("\(mill.city), \(mill.state)").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.down").foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "house.fill").foregroundStyle(Color.carterBlue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(yard.displayName).font(.subheadline).fontWeight(.semibold)
                                Text(yard.fullAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Schedule button
                    Button { showingScheduleSheet = true } label: {
                        Label("Schedule This Route", systemImage: "calendar.badge.plus")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(12)
                            .background(Color.orange).foregroundStyle(.white).cornerRadius(8)
                    }.buttonStyle(.plain)

                    if let route = vm.twoLegRoute {
                        TruckLegCard(title: "LEG 1: TRUCK TO MILL", leg: route.leg1, color: .orange)
                        TruckLegCard(title: "LEG 2: MILL TO YARD", leg: route.leg2, color: Color.carterBlue)

                        VStack(spacing: 6) {
                            Text("TRIP TOTAL").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                            Text(route.formattedTotalDistance)
                                .font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.carterBlue)
                            Text(route.formattedTotalDuration).font(.subheadline).fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray6)).cornerRadius(10)
                    }

                    if let fuel = vm.fuelEstimate { FuelEstimateCard(estimate: fuel) }
                    if !vm.weatherPoints.isEmpty { WeatherAlongRouteCard(points: vm.weatherPoints) }

                    Button {
                        vm.clearRoute(); mapViewModel.clearRoute(); onDismiss()
                    } label: {
                        Label("New Route", systemImage: "arrow.counterclockwise")
                            .font(.subheadline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color(.systemGray5)).cornerRadius(8)
                    }.buttonStyle(.plain).padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Trip Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingScheduleSheet) {
                ScheduleRouteSheet(
                    routeType: "truck",
                    mill: vm.selectedMill,
                    yard: vm.selectedYard,
                    truck: vm.selectedVehicle,
                    distance: vm.twoLegRoute?.formattedTotalDistance,
                    duration: vm.twoLegRoute?.totalDuration,
                    fuelCost: vm.fuelEstimate?.totalCost,
                    vm: scheduleVM ?? ScheduleViewModel(config: config),
                    onDone: { }
                )
            }
            .onAppear {
                if scheduleVM == nil { scheduleVM = ScheduleViewModel(config: config) }
            }
        }
    }
}

// MARK: - Settings

struct SettingsContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var dataStore
    @State private var updateStatus: UpdateCheckStatus = .idle
    @State private var latestVersion: String?
    @State private var updateURL: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    enum UpdateCheckStatus {
        case idle, checking, upToDate, updateAvailable, error(String)
    }

    var body: some View {
        @Bindable var config = config
        Form {
            Section("Diesel Fuel Settings") {
                HStack {
                    Text("Truck MPG"); Spacer()
                    TextField("MPG", value: $config.truckMPG, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                HStack {
                    Text("Tank Size (gal)"); Spacer()
                    TextField("Gallons", value: $config.tankSizeGallons, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("EIA API Key")
                    TextField("Enter EIA API key", text: $config.eiaApiKey)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("Get a free API key at eia.gov").font(.caption2).foregroundStyle(.secondary)
            }

            Section("Server") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                    TextField("http://logistics-ai.carterlumber.com", text: $config.intelliShiftBaseURL)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("One server handles everything: routing, geocoding, weather, diesel prices, IntelliShift vehicles, mills/yards, and schedule.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Manage") {
                NavigationLink { MillsSettingsView() } label: {
                    Label("Mills", systemImage: "building.2.fill")
                        .badge(dataStore.mills.count)
                }
                NavigationLink { YardsSettingsView() } label: {
                    Label("Yards", systemImage: "house.fill")
                        .badge(dataStore.yards.count)
                }
                NavigationLink { VehiclesSettingsView() } label: {
                    Label("Vehicles", systemImage: "truck.box.fill")
                }
                NavigationLink { ActivityLogView() } label: {
                    Label("Activity Log", systemImage: "list.bullet.clipboard")
                }
            }

            Section("Reference Data") {
                HStack {
                    Text("Mills"); Spacer()
                    Text("\(dataStore.mills.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Yards"); Spacer()
                    Text("\(dataStore.yards.count)").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Last refreshed"); Spacer()
                    if let when = dataStore.lastSyncedAt {
                        Text(when, style: .relative).foregroundStyle(.secondary)
                    } else {
                        Text("never (using cache or seed)").foregroundStyle(.secondary).italic()
                    }
                }
                Button {
                    Task { await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL) }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload from Server")
                        Spacer()
                        if dataStore.isSyncing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(dataStore.isSyncing)
                if let err = dataStore.lastSyncError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("Mills/Yards are fetched from the server on launch and cached locally so the app works offline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("App Info") {
                HStack {
                    Text("App")
                    Spacer()
                    Text("Carter Lumber Route Planner").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(currentVersion) (\(buildNumber))")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                Button {
                    Task { await checkForUpdates() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Check for Updates")
                        Spacer()
                        switch updateStatus {
                        case .idle:
                            EmptyView()
                        case .checking:
                            ProgressView().controlSize(.small)
                        case .upToDate:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .updateAvailable:
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        case .error:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }

                switch updateStatus {
                case .upToDate:
                    Text("You're running the latest version (\(currentVersion))")
                        .font(.caption).foregroundStyle(.green)
                case .updateAvailable:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(latestVersion ?? "?") is available!")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                        if let url = updateURL {
                            Text("Contact your administrator or visit the update link to install.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Link("Install Update", destination: URL(string: url)!)
                                .font(.caption).fontWeight(.semibold)
                        } else {
                            Text("Contact your administrator for the update.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                case .error(let msg):
                    Text(msg).font(.caption).foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Save") { config.save() } }
        }
    }

    private func checkForUpdates() async {
        updateStatus = .checking

        // Check the server for a version manifest
        let urlStr = "\(config.intelliShiftBaseURL)/api/app-version"
        guard let url = URL(string: urlStr) else {
            updateStatus = .error("Invalid server URL")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateStatus = .error("Server returned an error")
                return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let latest = json["version"] as? String else {
                updateStatus = .error("Invalid version response")
                return
            }

            latestVersion = latest
            updateURL = json["installURL"] as? String

            if compareVersions(current: currentVersion, latest: latest) {
                updateStatus = .updateAvailable
            } else {
                updateStatus = .upToDate
            }
        } catch {
            updateStatus = .error("Could not reach server: \(error.localizedDescription)")
        }
    }

    /// Returns true if latest > current
    private func compareVersions(current: String, latest: String) -> Bool {
        let c = current.split(separator: ".").compactMap { Int($0) }
        let l = latest.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, l.count) {
            let cv = i < c.count ? c[i] : 0
            let lv = i < l.count ? l[i] : 0
            if lv > cv { return true }
            if lv < cv { return false }
        }
        return false
    }
}
