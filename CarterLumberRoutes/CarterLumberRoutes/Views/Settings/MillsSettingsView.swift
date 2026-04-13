import SwiftUI

/// Admin list of Mills with search, create, edit, delete, and a "Geocode
/// missing" bulk action. Data is fetched live from the LocationDataStore
/// (which in turn pulls from /api/mills).
struct MillsSettingsView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var dataStore

    @State private var search: String = ""
    @State private var editing: Mill?             // nil when presenting "Add new"
    @State private var showingEditor = false
    @State private var showingGeocodeProgress = false
    @State private var geocodeResult: MillsYardsService.GeocodeAllResult?
    @State private var isGeocoding = false
    @State private var alertMessage: String?

    private var filteredMills: [Mill] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = dataStore.mills
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q)
                || $0.vendor.lowercased().contains(q)
                || $0.city.lowercased().contains(q)
                || $0.product.lowercased().contains(q)
        }
    }

    private var missingCoordCount: Int {
        dataStore.mills.filter { $0.lat == nil || $0.lon == nil }.count
    }

    var body: some View {
        List {
            if missingCoordCount > 0 {
                Section {
                    Button {
                        Task { await runGeocodeAll() }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            VStack(alignment: .leading) {
                                Text("Geocode \(missingCoordCount) missing").font(.subheadline.weight(.semibold))
                                Text("Adds lat/lon to mills that have an address but no coordinates.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isGeocoding { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isGeocoding)
                }
            }

            Section {
                ForEach(filteredMills) { mill in
                    Button {
                        editing = mill
                        showingEditor = true
                    } label: {
                        millRow(mill)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: deleteRows)
            } header: {
                HStack {
                    Text("\(filteredMills.count) of \(dataStore.mills.count)")
                    Spacer()
                    Text(search.isEmpty ? "Tap to edit" : "Tap to edit • swipe to delete")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Mills")
        .searchable(text: $search, placement: .navigationBarDrawer, prompt: "Search by name, vendor, city, product")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = nil
                    showingEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            MillEditorView(mill: editing) { result in
                showingEditor = false
                switch result {
                case .saved:   Task { await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL) }
                case .cancel:  break
                }
            }
        }
        .alert("Geocoding", isPresented: Binding(
            get: { geocodeResult != nil },
            set: { if !$0 { geocodeResult = nil } }
        ), presenting: geocodeResult) { _ in
            Button("OK") { geocodeResult = nil }
        } message: { r in
            var msg = "Geocoded \(r.succeeded) of \(r.total) mills."
            if r.failed > 0 {
                msg += "\n\n\(r.failed) failed:\n" + r.failures.prefix(5).map { "• \($0.name)" }.joined(separator: "\n")
                if r.failures.count > 5 { msg += "\n…and \(r.failures.count - 5) more." }
            }
            Text(msg)
        }
        .alert("Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        ), presenting: alertMessage) { _ in
            Button("OK") { alertMessage = nil }
        } message: { msg in Text(msg) }
    }

    // MARK: - Row

    @ViewBuilder
    private func millRow(_ mill: Mill) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mill.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    if !mill.product.isEmpty { productBadge(mill.product) }
                    if !mill.vendor.isEmpty {
                        Text(mill.vendor).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(mill.city), \(mill.stateZip)").font(.caption).foregroundStyle(.secondary)
                if mill.lat == nil || mill.lon == nil {
                    Text("📍 No coordinates yet")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func productBadge(_ product: String) -> some View {
        Text(product.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.green.opacity(0.15)))
            .foregroundStyle(.green)
    }

    // MARK: - Actions

    private func deleteRows(offsets: IndexSet) {
        let toDelete = offsets.compactMap { filteredMills[safe: $0] }
        Task { await deleteMills(toDelete) }
    }

    private func deleteMills(_ mills: [Mill]) async {
        let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
        for mill in mills {
            guard let uuid = mill.uuid else { continue }
            do {
                try await service.deleteMill(uuid: uuid)
            } catch {
                alertMessage = "Delete failed for \(mill.name): \(error.localizedDescription)"
                break
            }
        }
        await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL)
    }

    private func runGeocodeAll() async {
        isGeocoding = true
        defer { isGeocoding = false }
        do {
            let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
            let result = try await service.geocodeAllMills()
            await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL)
            geocodeResult = result
        } catch {
            alertMessage = "Geocode failed: \(error.localizedDescription)"
        }
    }
}

/// Safe index accessor — returns nil instead of crashing on out-of-bounds.
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
