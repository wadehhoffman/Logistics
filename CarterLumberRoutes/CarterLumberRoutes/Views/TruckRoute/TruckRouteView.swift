// TruckRouteView is now inlined as TruckRouteContentView in ContentView.swift
// This file kept for TruckLegCard reuse.
import SwiftUI

struct TruckLegCard: View {
    let title: String
    let leg: RouteLeg
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                VStack(alignment: .leading) {
                    Text(leg.from).font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.down").font(.caption2)
                    Text(leg.to).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(leg.formattedDistance)
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(color)
                    Text(leg.formattedDuration)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(color.opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.2)))
    }
}
