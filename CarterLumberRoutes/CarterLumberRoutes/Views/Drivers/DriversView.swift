import SwiftUI

/// Branch 570 driver dashboard mirroring the web's Drivers modal.
/// Shows live HOS tracking, vehicle assignments, medical card compliance,
/// and CDL endorsements for every operator.
struct DriversView: View {
    @Environment(AppConfiguration.self) private var config
    @State private var viewModel: DriversViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm: vm)
            } else {
                ProgressView().onAppear { viewModel = DriversViewModel(config: config) }
            }
        }
    }

    @ViewBuilder
    private func content(vm: DriversViewModel) -> some View {
        @Bindable var vm = vm
        List {
            summarySection(vm: vm)
            driversSection(vm: vm)
        }
        .listStyle(.insetGrouped)
        .searchable(text: $vm.searchText, placement: .navigationBarDrawer, prompt: "Search by name, vehicle, city")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await vm.load() } } label: {
                    if vm.isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(vm.isLoading)
            }
        }
        .task { if vm.drivers.isEmpty { await vm.load() } }
        .refreshable { await vm.load() }
        .overlay {
            if let err = vm.errorMessage, vm.drivers.isEmpty {
                ContentUnavailableView("Could not load drivers",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err))
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(vm: DriversViewModel) -> some View {
        Section {
            HStack(spacing: 16) {
                summaryItem(value: "\(vm.onShiftCount)", label: "On Shift", color: .green)
                summaryItem(value: "\(vm.offShiftCount)", label: "Off Shift", color: .secondary)
                summaryItem(value: String(format: "%.1fh", vm.averageWeekHours), label: "Avg Week", color: Color.carterBlue)
                if vm.lowDailyCount > 0 {
                    summaryItem(value: "\(vm.lowDailyCount)", label: "Low Daily", color: .orange)
                }
                if vm.expiredMedCardCount > 0 {
                    summaryItem(value: "\(vm.expiredMedCardCount)", label: "Expired Med", color: .red)
                }
            }
        } header: {
            HStack {
                Text("\(vm.drivers.count) drivers")
                Spacer()
                if !vm.asOfLabel.isEmpty {
                    Text("as of \(vm.asOfLabel)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Driver rows

    @ViewBuilder
    private func driversSection(vm: DriversViewModel) -> some View {
        Section {
            if vm.isLoading && vm.drivers.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                ForEach(vm.filteredDrivers) { driver in
                    driverRow(driver)
                }
            }
        }
    }

    @ViewBuilder
    private func driverRow(_ driver: Driver) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + status
            HStack(spacing: 8) {
                Circle()
                    .fill(driver.status == .onShift ? Color.green : Color(.systemGray4))
                    .frame(width: 10, height: 10)
                    .shadow(color: driver.status == .onShift ? .green.opacity(0.5) : .clear, radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(driver.name).font(.subheadline.weight(.semibold))
                    if let shift = driver.shiftStartLabel {
                        Text("Since \(shift)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !driver.employeeId.isEmpty {
                    Text(driver.employeeId).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
            }

            // Vehicle + location
            if let v = driver.currentVehicle {
                HStack(spacing: 6) {
                    Image(systemName: "truck.box.fill").font(.caption2).foregroundStyle(.blue)
                    Text(v.name).font(.caption.weight(.semibold)).monospaced()
                    if !v.locationLabel.isEmpty {
                        Text("•").foregroundStyle(.secondary)
                        Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(.secondary)
                        Text(v.locationLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "truck.box").font(.caption2).foregroundStyle(.tertiary)
                    Text("No vehicle assigned").font(.caption).foregroundStyle(.tertiary).italic()
                }
            }

            // HOS bars
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY (11h)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    HOSProgressBar(
                        used: driver.todayActualHours,
                        cap: 11,
                        remaining: driver.dailyRemaining
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEEK (70h)").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    HOSProgressBar(
                        used: driver.weekActualHours,
                        cap: 70,
                        remaining: driver.weeklyRemaining
                    )
                }
                if driver.weekPlannedHours > 0 {
                    VStack(alignment: .center, spacing: 2) {
                        Text("PLANNED").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(String(format: "%.1fh", driver.weekPlannedHours))
                            .font(.caption.weight(.semibold))
                    }
                    .frame(width: 50)
                }
            }

            // Compliance row
            HStack(spacing: 8) {
                medCardBadge(driver.medicalCardStatus)
                if let dateLabel = driver.medCardDateLabel {
                    Text(dateLabel).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                ForEach(driver.endorsements, id: \.self) { endorsement in
                    endorsementBadge(endorsement)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Components

    @ViewBuilder
    private func medCardBadge(_ status: Driver.MedCardStatus) -> some View {
        let (label, bg, fg): (String, Color, Color) = {
            switch status {
            case .valid:        return ("Valid",    Color.green.opacity(0.15), .green)
            case .expiringSoon: return ("Expiring", Color.orange.opacity(0.2), .orange)
            case .expired:      return ("Expired",  Color.red.opacity(0.15),   .red)
            case .unknown:      return ("N/A",      Color.gray.opacity(0.1),   .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .foregroundStyle(fg)
    }

    @ViewBuilder
    private func endorsementBadge(_ endorsement: String) -> some View {
        Text(endorsement)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.12)))
            .foregroundStyle(Color.carterBlue)
    }
}

// MARK: - HOS Progress Bar

/// Reusable horizontal bar showing hours used vs. cap, color-coded by
/// remaining hours: green > 4h, yellow 2–4h, red < 2h.
struct HOSProgressBar: View {
    let used: Double
    let cap: Double
    let remaining: Double

    private var fraction: Double { min(1, max(0, used / cap)) }
    private var barColor: Color {
        if remaining > 4 { return .green }
        if remaining > 2 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 14)
            .overlay {
                Text(String(format: "%.1fh left", remaining))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            Text(String(format: "%.1f / %.0fh", used, cap))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
    }
}
