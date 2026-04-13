import SwiftUI

/// Admin list of Yards with search, create, edit, delete. Mirrors
/// MillsSettingsView but with editable lat/lon (yards always need coords
/// for the map).
struct YardsSettingsView: View {
    @Environment(AppConfiguration.self) private var config
    @Environment(LocationDataStore.self) private var dataStore

    @State private var search: String = ""
    @State private var editing: Yard?
    @State private var showingEditor = false
    @State private var alertMessage: String?

    private var filteredYards: [Yard] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let all = dataStore.yards
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.storeNumber.lowercased().contains(q)
                || $0.posNumber.lowercased().contains(q)
                || $0.city.lowercased().contains(q)
                || $0.state.lowercased().contains(q)
                || $0.market.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredYards) { yard in
                    Button {
                        editing = yard
                        showingEditor = true
                    } label: { yardRow(yard) }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: deleteRows)
            } header: {
                HStack {
                    Text("\(filteredYards.count) of \(dataStore.yards.count)")
                    Spacer()
                    Text(search.isEmpty ? "Tap to edit" : "Tap to edit • swipe to delete")
                }
                .font(.caption)
            }
        }
        .navigationTitle("Yards")
        .searchable(text: $search, placement: .navigationBarDrawer, prompt: "Search by #, city, state, market")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = nil
                    showingEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            YardEditorView(yard: editing) { result in
                showingEditor = false
                switch result {
                case .saved:  Task { await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL) }
                case .cancel: break
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        ), presenting: alertMessage) { _ in
            Button("OK") { alertMessage = nil }
        } message: { Text($0) }
    }

    @ViewBuilder
    private func yardRow(_ yard: Yard) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(yard.posNumber).font(.subheadline.weight(.semibold)).monospaced()
                    if !yard.storeType.isEmpty {
                        Text(yard.storeType)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundStyle(.blue)
                    }
                }
                Text("\(yard.city), \(yard.state) \(yard.zip)").font(.caption).foregroundStyle(.secondary)
                if !yard.market.isEmpty {
                    Text(yard.market).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func deleteRows(offsets: IndexSet) {
        let toDelete = offsets.compactMap { filteredYards[safe: $0] }
        Task { await deleteYards(toDelete) }
    }

    private func deleteYards(_ yards: [Yard]) async {
        let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
        for yard in yards {
            guard let uuid = yard.uuid else { continue }
            do {
                try await service.deleteYard(uuid: uuid)
            } catch {
                alertMessage = "Delete failed for yard #\(yard.posNumber): \(error.localizedDescription)"
                break
            }
        }
        await dataStore.refresh(serverBaseURL: config.intelliShiftBaseURL)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
