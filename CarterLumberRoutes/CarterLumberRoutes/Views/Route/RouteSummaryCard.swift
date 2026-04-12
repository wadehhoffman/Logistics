import SwiftUI

struct RouteSummaryCard: View {
    let route: RouteResult

    var body: some View {
        VStack(spacing: 8) {
            Text("ROUTE SUMMARY")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Big distance number
            Text(route.formattedDistance)
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(Color(red: 0.17, green: 0.37, blue: 0.54))

            Text(String(format: "%.1f km", route.distanceKm))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Est. Drive Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(route.formattedDuration)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.17, green: 0.37, blue: 0.54))
            }

            if route.isFallback {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(route.fallbackNote ?? "Estimated distance (routing API unavailable)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
