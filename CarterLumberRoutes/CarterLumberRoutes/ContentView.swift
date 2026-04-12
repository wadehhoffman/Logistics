import SwiftUI

struct ContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var selectedPage: AppPage = .singleRoute
    @State private var showMenu = false

    enum AppPage: String, CaseIterable, Identifiable {
        case singleRoute = "Route Planner"
        case truckRoute = "Truck Route"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .singleRoute: return "arrow.triangle.turn.up.right.diamond"
            case .truckRoute: return "truck.box.fill"
            case .settings: return "gear"
            }
        }

        var subtitle: String {
            switch self {
            case .singleRoute: return "Mill to Yard routing"
            case .truckRoute: return "Live truck + 2-leg route"
            case .settings: return "API keys, fuel settings"
            }
        }
    }

    var body: some View {
        ZStack {
            mainContent.disabled(showMenu)

            if showMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { showMenu = false } }
                    .transition(.opacity)
            }

            sideMenu
        }
        .animation(.easeOut(duration: 0.25), value: showMenu)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        NavigationStack {
            Group {
                switch selectedPage {
                case .singleRoute:  SingleRouteContentView()
                case .truckRoute:   TruckRouteContentView()
                case .settings:     SettingsContentView()
                }
            }
            .navigationTitle(selectedPage.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { showMenu = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundStyle(Color.carterBlue)
                    }
                }
            }
        }
    }

    // MARK: - Side Menu

    private var sideMenu: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 32)).foregroundStyle(.white)
                    Text("Carter Lumber")
                        .font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    Text("Route Planner")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24).padding(.top, 20)
                .background(LinearGradient(
                    colors: [Color.carterDarkBlue, Color.carterBlue],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))

                VStack(spacing: 4) {
                    ForEach(AppPage.allCases) { page in menuItem(page: page) }
                }
                .padding(.top, 12).padding(.horizontal, 12)

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("58 mills / 238 yards").font(.caption2).foregroundStyle(.tertiary)
                    Text("v1.0.0").font(.caption2).foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .offset(x: showMenu ? 0 : -UIScreen.main.bounds.width)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }

    private func menuItem(page: AppPage) -> some View {
        Button {
            selectedPage = page
            withAnimation(.easeOut(duration: 0.25)) { showMenu = false }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: page.icon)
                    .font(.title3).frame(width: 28)
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
            .background(selectedPage == page ? Color.carterBlue : Color.clear)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single Route (collapsing picker → metrics)

struct SingleRouteContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: SingleRouteViewModel?
    @State private var mapViewModel = MapViewModel()
    @State private var showingMillPicker = false
    @State private var showingYardPicker = false
    @State private var pickersExpanded = true

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
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top half: Map
                MapContainerView(
                    routeCoordinates: mapViewModel.routeCoordinates,
                    annotations: mapViewModel.allAnnotations,
                    isFallbackRoute: mapViewModel.isFallbackRoute,
                    showTrafficLayer: mapViewModel.showTrafficLayer
                )
                .frame(height: geo.size.height * 0.5)

                Divider()

                // Bottom half: pickers or results
                ScrollView {
                    VStack(spacing: 12) {
                        // Collapsed route summary strip (when route exists and pickers hidden)
                        if vm.routeResult != nil {
                            collapsedPickerStrip(vm: vm)
                        }

                        // Expanded pickers
                        if pickersExpanded || vm.routeResult == nil {
                            pickerSection(vm: vm)
                        }

                        // Error
                        if let error = vm.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                                .padding(10).frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1)).cornerRadius(6)
                        }

                        // Results metrics
                        if let route = vm.routeResult {
                            RouteSummaryCard(route: route)
                            if let fuel = vm.fuelEstimate { FuelEstimateCard(estimate: fuel) }
                            if !vm.weatherPoints.isEmpty {
                                WeatherAlongRouteCard(points: vm.weatherPoints)
                            } else if vm.isFetchingWeather {
                                ProgressView("Fetching weather...").padding()
                            }

                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    vm.clearRoute()
                                    mapViewModel.clearRoute()
                                    pickersExpanded = true
                                }
                            } label: {
                                Label("New Route", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .frame(maxWidth: .infinity).padding(12)
                                    .background(Color(.systemGray5)).cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { mapViewModel.showTrafficLayer.toggle() } label: {
                    Image(systemName: mapViewModel.showTrafficLayer ? "car.fill" : "car")
                }
            }
        }
        .sheet(isPresented: $showingMillPicker) {
            MillPickerView(mills: locationStore.mills) { mill in
                Task { await vm.selectMill(mill) }
            }
        }
        .sheet(isPresented: $showingYardPicker) {
            YardPickerView(yards: locationStore.yards) { yard in
                vm.selectedYard = yard
            }
        }
    }

    @ViewBuilder
    private func collapsedPickerStrip(vm: SingleRouteViewModel) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { pickersExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "building.2.fill").foregroundStyle(.red).font(.caption)
                Text(vm.selectedMill?.name ?? "").font(.caption).lineLimit(1)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "house.fill").foregroundStyle(Color.carterBlue).font(.caption)
                Text(vm.selectedYard?.displayName ?? "").font(.caption).lineLimit(1)
                Spacer()
                Image(systemName: pickersExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerSection(vm: SingleRouteViewModel) -> some View {
        VStack(spacing: 12) {
            // Mill Picker
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
                }
                .buttonStyle(.plain)
                if let mill = vm.selectedMill {
                    Text(mill.address).font(.caption).foregroundStyle(.secondary)
                }
            }

            // Yard Picker
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
                }
                .buttonStyle(.plain)
                if let yard = vm.selectedYard {
                    Text("\(yard.fullAddress) — \(yard.manager)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Route Button
            Button {
                Task {
                    await vm.calculateRoute()
                    if let result = vm.routeResult, let mill = vm.selectedMill,
                       let coord = vm.millCoordinate, let yard = vm.selectedYard {
                        mapViewModel.setRoute(result: result, mill: mill, millCoord: coord, yard: yard)
                        withAnimation(.spring(duration: 0.3)) { pickersExpanded = false }
                    }
                }
            } label: {
                HStack {
                    if vm.isCalculating { ProgressView().controlSize(.small).tint(.white) }
                    Text(vm.isCalculating ? "Calculating..." : "Get Route & Distance")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(14)
                .background(vm.canCalculate ? Color.carterBlue : Color.gray)
                .foregroundStyle(.white).cornerRadius(8)
            }
            .disabled(!vm.canCalculate)
        }
    }
}

// MARK: - Truck Route (collapsing picker → metrics)

struct TruckRouteContentView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var locationStore
    @State private var viewModel: TruckRouteViewModel?
    @State private var mapViewModel = MapViewModel()
    @State private var showingTruckPicker = false
    @State private var showingMillPicker = false
    @State private var showingYardPicker = false
    @State private var pickersExpanded = true

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
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top half: Map
                MapContainerView(
                    routeCoordinates: mapViewModel.routeCoordinates,
                    annotations: mapViewModel.allAnnotations,
                    isFallbackRoute: mapViewModel.isFallbackRoute,
                    showTrafficLayer: mapViewModel.showTrafficLayer
                )
                .frame(height: geo.size.height * 0.5)

                Divider()

                // Bottom half
                ScrollView {
                    VStack(spacing: 12) {
                        // Collapsed strip
                        if vm.twoLegRoute != nil {
                            collapsedPickerStrip(vm: vm)
                        }

                        // Expanded pickers
                        if pickersExpanded || vm.twoLegRoute == nil {
                            pickerSection(vm: vm)
                        }

                        if let error = vm.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                                .padding(10).background(Color.red.opacity(0.1)).cornerRadius(6)
                        }

                        // Results
                        if let route = vm.twoLegRoute {
                            TruckLegCard(title: "LEG 1: TRUCK TO MILL", leg: route.leg1, color: .orange)
                            TruckLegCard(title: "LEG 2: MILL TO YARD", leg: route.leg2, color: Color.carterBlue)

                            VStack(spacing: 6) {
                                Text("TRIP TOTAL").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                                Text(route.formattedTotalDistance)
                                    .font(.system(size: 28, weight: .heavy)).foregroundStyle(Color.carterBlue)
                                Text(route.formattedTotalDuration)
                                    .font(.subheadline).fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemGray6)).cornerRadius(10)

                            if let fuel = vm.fuelEstimate { FuelEstimateCard(estimate: fuel) }
                            if !vm.weatherPoints.isEmpty { WeatherAlongRouteCard(points: vm.weatherPoints) }

                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    vm.clearRoute(); mapViewModel.clearRoute()
                                    pickersExpanded = true
                                }
                            } label: {
                                Label("New Route", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .frame(maxWidth: .infinity).padding(12)
                                    .background(Color(.systemGray5)).cornerRadius(8)
                            }
                            .buttonStyle(.plain).padding(.top, 4)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingTruckPicker) {
            TruckPickerView(vehicles: vm.vehicles, isLoading: vm.isLoadingTrucks) { truck in
                vm.selectedVehicle = truck
            }
        }
        .sheet(isPresented: $showingMillPicker) {
            MillPickerView(mills: locationStore.mills) { mill in
                Task { await vm.selectMill(mill) }
            }
        }
        .sheet(isPresented: $showingYardPicker) {
            YardPickerView(yards: locationStore.yards) { yard in
                vm.selectedYard = yard
            }
        }
    }

    @ViewBuilder
    private func collapsedPickerStrip(vm: TruckRouteViewModel) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { pickersExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "truck.box.fill").foregroundStyle(.blue).font(.caption)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.secondary)
                Image(systemName: "building.2.fill").foregroundStyle(.red).font(.caption)
                Text(vm.selectedMill?.name ?? "").font(.caption).lineLimit(1)
                Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.secondary)
                Image(systemName: "house.fill").foregroundStyle(Color.carterBlue).font(.caption)
                Text(vm.selectedYard?.displayName ?? "").font(.caption).lineLimit(1)
                Spacer()
                Image(systemName: pickersExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10).background(Color(.systemGray6)).cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickerSection(vm: TruckRouteViewModel) -> some View {
        VStack(spacing: 12) {
            // Truck
            VStack(alignment: .leading, spacing: 4) {
                Text("1. SELECT TRUCK").font(.caption2).fontWeight(.bold).foregroundStyle(.secondary)
                Button {
                    if vm.vehicles.isEmpty { Task { await vm.loadTrucks() } }
                    showingTruckPicker = true
                } label: {
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
                }
                .buttonStyle(.plain)
                if let truck = vm.selectedVehicle {
                    Text("\(truck.locationDescription) — \(truck.status.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Mill
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
                }
                .buttonStyle(.plain)
            }

            // Yard
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
                }
                .buttonStyle(.plain)
            }

            // Calculate
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
                        withAnimation(.spring(duration: 0.3)) { pickersExpanded = false }
                    }
                }
            } label: {
                HStack {
                    if vm.isCalculating { ProgressView().controlSize(.small).tint(.white) }
                    Text(vm.isCalculating ? "Calculating..." : "Calculate Truck Route")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(14)
                .background(vm.canCalculate ? Color.carterBlue : .gray)
                .foregroundStyle(.white).cornerRadius(8)
            }
            .disabled(!vm.canCalculate)
        }
    }
}

// MARK: - Settings

struct SettingsContentView: View {
    @Environment(AppConfiguration.self) private var config

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

            Section("IntelliShift") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                    TextField("http://localhost:3003", text: $config.intelliShiftBaseURL)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("Connects to your Node.js server for truck data.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Mapbox") {
                HStack {
                    Text("Token"); Spacer()
                    if config.mapboxToken.isEmpty {
                        Text("Not configured").font(.caption).foregroundStyle(.red)
                    } else {
                        Text("\(config.mapboxToken.prefix(12))...")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                HStack { Text("App"); Spacer(); Text("Carter Lumber Route Planner").foregroundStyle(.secondary) }
                HStack { Text("Version"); Spacer(); Text("1.0.0").foregroundStyle(.secondary) }
                HStack { Text("Data"); Spacer(); Text("58 mills, 238 yards").foregroundStyle(.secondary) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { config.save() }
            }
        }
    }
}
