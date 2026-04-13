import SwiftUI

/// Add / Edit form for a Mill. On save, server auto-geocodes the address
/// and returns the saved record with lat/lon populated.
struct MillEditorView: View {
    let mill: Mill?
    let onDismiss: (Result) -> Void

    @Environment(AppConfiguration.self) private var config
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var product: String
    @State private var vendor: String
    @State private var street: String
    @State private var city: String
    @State private var stateZip: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    enum Result { case saved, cancel }

    init(mill: Mill?, onDismiss: @escaping (Result) -> Void) {
        self.mill = mill
        self.onDismiss = onDismiss
        _name     = State(initialValue: mill?.name     ?? "")
        _product  = State(initialValue: mill?.product  ?? "YP")
        _vendor   = State(initialValue: mill?.vendor   ?? "")
        _street   = State(initialValue: mill?.street   ?? "")
        _city     = State(initialValue: mill?.city     ?? "")
        _stateZip = State(initialValue: mill?.stateZip ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !street.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
            && !stateZip.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var composedAddress: String {
        "\(street), \(city), \(stateZip)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledField(label: "Name", text: $name)
                    LabeledField(label: "Product", text: $product, placeholder: "YP, OSB, etc.")
                    LabeledField(label: "Vendor #", text: $vendor)
                }
                Section("Address") {
                    LabeledField(label: "Street", text: $street)
                    LabeledField(label: "City", text: $city)
                    LabeledField(label: "State / ZIP", text: $stateZip, placeholder: "GA 31539")
                }
                Section {
                    Text("Coordinates are auto-geocoded from the address on save.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(mill == nil ? "Add Mill" : "Edit Mill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onDismiss(.cancel); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView().controlSize(.small) }
                        else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payload = MillsYardsService.CreateMillPayload(
            name: name.trimmingCharacters(in: .whitespaces),
            product: product.trimmingCharacters(in: .whitespaces),
            vendor: vendor.trimmingCharacters(in: .whitespaces),
            street: street.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            stateZip: stateZip.trimmingCharacters(in: .whitespaces),
            address: composedAddress
        )

        do {
            let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
            if let uuid = mill?.uuid {
                _ = try await service.updateMill(uuid: uuid, payload: payload)
            } else {
                _ = try await service.createMill(payload)
            }
            onDismiss(.saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Small labeled row used across Mill + Yard editors. Keeps the form
/// visually consistent without repeating HStack boilerplate.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var autocap: TextInputAutocapitalization = .words

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
        }
    }
}
