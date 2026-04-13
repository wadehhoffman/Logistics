import SwiftUI

/// Add / Edit form for a Yard. Yards have user-editable lat/lon (server
/// stores them as-is; no auto-geocoding). Validates coordinate ranges.
struct YardEditorView: View {
    let yard: Yard?
    let onDismiss: (Result) -> Void

    @Environment(AppConfiguration.self) private var config
    @Environment(\.dismiss) private var dismiss

    @State private var storeNumber: String
    @State private var posNumber: String
    @State private var storeType: String
    @State private var street: String
    @State private var city: String
    @State private var state: String
    @State private var zip: String
    @State private var latStr: String
    @State private var lonStr: String
    @State private var manager: String
    @State private var market: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    enum Result { case saved, cancel }

    init(yard: Yard?, onDismiss: @escaping (Result) -> Void) {
        self.yard = yard
        self.onDismiss = onDismiss
        _storeNumber = State(initialValue: yard?.storeNumber ?? "")
        _posNumber   = State(initialValue: yard?.posNumber   ?? "")
        _storeType   = State(initialValue: yard?.storeType   ?? "")
        _street      = State(initialValue: yard?.street      ?? "")
        _city        = State(initialValue: yard?.city        ?? "")
        _state       = State(initialValue: yard?.state       ?? "")
        _zip         = State(initialValue: yard?.zip         ?? "")
        _latStr      = State(initialValue: yard.map { String($0.lat) } ?? "")
        _lonStr      = State(initialValue: yard.map { String($0.lon) } ?? "")
        _manager     = State(initialValue: yard?.manager     ?? "")
        _market      = State(initialValue: yard?.market      ?? "")
    }

    private var latValue: Double? { Double(latStr.trimmingCharacters(in: .whitespaces)) }
    private var lonValue: Double? { Double(lonStr.trimmingCharacters(in: .whitespaces)) }

    private var coordinatesValid: Bool {
        // Allow empty for creation (server will accept nil), but if provided
        // must be in range
        let latOK = latStr.isEmpty || (latValue.map { (-90...90).contains($0) } ?? false)
        let lonOK = lonStr.isEmpty || (lonValue.map { (-180...180).contains($0) } ?? false)
        return latOK && lonOK
    }

    private var canSave: Bool {
        !storeNumber.trimmingCharacters(in: .whitespaces).isEmpty
            && !city.trimmingCharacters(in: .whitespaces).isEmpty
            && !state.trimmingCharacters(in: .whitespaces).isEmpty
            && coordinatesValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledField(label: "Store #", text: $storeNumber, placeholder: "900-459")
                    LabeledField(label: "POS #",   text: $posNumber)
                    LabeledField(label: "Store Type", text: $storeType, placeholder: "CCP, LUMBER, etc.")
                }
                Section("Address") {
                    LabeledField(label: "Street", text: $street)
                    LabeledField(label: "City",   text: $city)
                    HStack {
                        LabeledField(label: "State", text: $state, placeholder: "GA", autocap: .characters)
                            .frame(width: 80)
                        LabeledField(label: "ZIP",   text: $zip, placeholder: "31539", autocap: .never)
                    }
                }
                Section("Coordinates") {
                    LabeledField(label: "Latitude",  text: $latStr, placeholder: "31.257526", autocap: .never)
                    LabeledField(label: "Longitude", text: $lonStr, placeholder: "-85.403661", autocap: .never)
                    if !coordinatesValid {
                        Text("Latitude must be -90..90 and longitude must be -180..180.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                Section("Operations") {
                    LabeledField(label: "Manager", text: $manager)
                    LabeledField(label: "Market",  text: $market)
                }
                if let err = errorMessage {
                    Section { Text(err).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(yard == nil ? "Add Yard" : "Edit Yard")
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

        let payload = MillsYardsService.CreateYardPayload(
            storeNumber: storeNumber.trimmingCharacters(in: .whitespaces),
            posNumber: posNumber.trimmingCharacters(in: .whitespaces),
            storeType: storeType.trimmingCharacters(in: .whitespaces),
            street: street.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            state: state.trimmingCharacters(in: .whitespaces).uppercased(),
            zip: zip.trimmingCharacters(in: .whitespaces),
            lat: latValue,
            lon: lonValue,
            manager: manager.trimmingCharacters(in: .whitespaces),
            market: market.trimmingCharacters(in: .whitespaces)
        )

        do {
            let service = MillsYardsService(baseURL: config.intelliShiftBaseURL)
            if let uuid = yard?.uuid {
                _ = try await service.updateYard(uuid: uuid, payload: payload)
            } else {
                _ = try await service.createYard(payload)
            }
            onDismiss(.saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
