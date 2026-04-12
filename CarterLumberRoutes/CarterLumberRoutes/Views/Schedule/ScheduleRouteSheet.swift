import SwiftUI

struct ScheduleRouteSheet: View {
    let routeType: String   // "single" or "truck"
    let mill: Mill?
    let yard: Yard?
    let truck: Vehicle?
    let distance: String?
    let duration: Double?
    let fuelCost: Double?
    let vm: ScheduleViewModel
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scheduledDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var scheduledTime = Calendar.current.date(from: DateComponents(hour: 6, minute: 0))!
    @State private var notes = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    if let mill = mill {
                        HStack(spacing: 8) {
                            Image(systemName: "building.2.fill").foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text(mill.name).font(.subheadline).fontWeight(.semibold)
                                Text("\(mill.city), \(mill.state)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let yard = yard {
                        HStack(spacing: 8) {
                            Image(systemName: "house.fill").foregroundStyle(Color.carterBlue)
                            VStack(alignment: .leading) {
                                Text(yard.displayName).font(.subheadline).fontWeight(.semibold)
                                Text(yard.fullAddress).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let dist = distance {
                        HStack { Text("Distance"); Spacer(); Text(dist).foregroundStyle(.secondary) }
                    }
                    if let truck = truck {
                        HStack(spacing: 8) {
                            Image(systemName: "truck.box.fill").foregroundStyle(.blue)
                            Text(truck.name).font(.subheadline)
                        }
                    }
                }

                Section("Schedule For") {
                    DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
                    DatePicker("Time", selection: $scheduledTime, displayedComponents: .hourAndMinute)
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Schedule Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Schedule").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        // Combine date + time
        let calendar = Calendar.current
        let dateComps = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
        let timeComps = calendar.dateComponents([.hour, .minute], from: scheduledTime)
        var combined = DateComponents()
        combined.year = dateComps.year
        combined.month = dateComps.month
        combined.day = dateComps.day
        combined.hour = timeComps.hour
        combined.minute = timeComps.minute
        let finalDate = calendar.date(from: combined) ?? scheduledDate

        let success = await vm.createSchedule(
            scheduledAt: finalDate,
            type: routeType,
            mill: mill,
            yard: yard,
            truck: truck,
            distance: distance,
            duration: duration,
            fuelCost: fuelCost,
            notes: notes
        )

        if success {
            dismiss()
            onDone()
        }
    }
}
