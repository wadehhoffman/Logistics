import SwiftUI

struct MillPickerView: View {
    let mills: [Mill]
    let onSelect: (Mill) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var productFilter: Mill.ProductType?

    private var filteredMills: [Mill] {
        var result = mills
        if let filter = productFilter {
            result = result.filter { $0.productType == filter }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) ||
                $0.city.lowercased().contains(q) ||
                $0.state.lowercased().contains(q) ||
                $0.vendor.contains(q)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredMills) { mill in
                    Button {
                        onSelect(mill)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mill.name)
                                    .font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                Text(mill.product)
                                    .font(.caption2).fontWeight(.bold)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(mill.productType == .osb ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            Text("\(mill.city), \(mill.state)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Vendor: \(mill.vendor)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search mills...")
            .navigationTitle("Select Mill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All") { productFilter = nil }
                        Button("Yellow Pine (YP)") { productFilter = .yp }
                        Button("OSB") { productFilter = .osb }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

struct YardPickerView: View {
    let yards: [Yard]
    let onSelect: (Yard) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var stateFilter: String?

    private var filteredYards: [Yard] {
        var result = yards
        if let filter = stateFilter {
            result = result.filter { $0.state == filter }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.posNumber.contains(q) ||
                $0.city.lowercased().contains(q) ||
                $0.state.lowercased().contains(q) ||
                $0.manager.lowercased().contains(q) ||
                $0.market.lowercased().contains(q)
            }
        }
        return result
    }

    private var uniqueStates: [String] {
        Array(Set(yards.map(\.state))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredYards) { yard in
                    Button {
                        onSelect(yard)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("#\(yard.posNumber) — \(yard.city), \(yard.state)")
                                    .font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                Text(yard.storeType)
                                    .font(.caption2).fontWeight(.bold)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .cornerRadius(4)
                            }
                            Text("\(yard.street), \(yard.zip)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(yard.manager)
                                    .font(.caption2)
                                Spacer()
                                Text(yard.market)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Search yards...")
            .navigationTitle("Select Yard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All States") { stateFilter = nil }
                        ForEach(uniqueStates, id: \.self) { state in
                            Button(FormatHelpers.stateName(for: state)) { stateFilter = state }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}
