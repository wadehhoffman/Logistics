import SwiftUI

struct WeatherAlongRouteCard: View {
    let points: [WeatherPoint]

    var body: some View {
        VStack(spacing: 8) {
            Text("WEATHER ALONG ROUTE")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(.blue.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(points) { point in
                HStack(spacing: 12) {
                    Image(systemName: point.icon)
                        .font(.title2)
                        .frame(width: 36)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.label)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        Text(point.description)
                            .font(.caption)
                        Text("Humidity: \(point.humidity)% | Wind: \(point.windSpeed) mph")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("\(point.temperature)\u{00B0}F")
                            .font(.title3).fontWeight(.bold)
                        Text("Feels \(point.feelsLike)\u{00B0}")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if point.id != points.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2)))
    }
}
