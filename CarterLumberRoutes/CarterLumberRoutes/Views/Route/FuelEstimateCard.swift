import SwiftUI

struct FuelEstimateCard: View {
    let estimate: FuelEstimate

    var body: some View {
        VStack(spacing: 8) {
            Text("FUEL ESTIMATE")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(Color.green.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let cost = estimate.totalCost {
                Text(String(format: "$%.2f", cost))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.green)
            }

            Text(estimate.formattedGallons)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Label("\(estimate.fuelStops) stop\(estimate.fuelStops == 1 ? "" : "s")", systemImage: "fuelpump.fill")
                    .font(.caption)
                Spacer()
                if let avg = estimate.averagePrice {
                    Text("Avg: \(String(format: "$%.3f", avg))/gal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Per-state breakdown table
            if !estimate.perStateBreakdown.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("State").font(.caption2).fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Price").font(.caption2).fontWeight(.bold)
                            .frame(width: 70, alignment: .trailing)
                        Text("Miles").font(.caption2).fontWeight(.bold)
                            .frame(width: 55, alignment: .trailing)
                        Text("Cost").font(.caption2).fontWeight(.bold)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color.green.opacity(0.15))

                    ForEach(estimate.perStateBreakdown) { detail in
                        HStack {
                            Text(detail.stateName)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "$%.3f", detail.pricePerGallon))
                                .font(.caption)
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "%.0f", detail.miles))
                                .font(.caption)
                                .frame(width: 55, alignment: .trailing)
                            Text(String(format: "$%.2f", detail.estimatedCost))
                                .font(.caption).fontWeight(.semibold)
                                .frame(width: 60, alignment: .trailing)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3)))
            }
        }
        .padding()
        .background(Color.green.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2)))
    }
}
