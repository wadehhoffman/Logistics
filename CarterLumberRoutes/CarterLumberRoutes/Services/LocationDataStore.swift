import Foundation
import SwiftUI

@Observable
final class LocationDataStore {
    private(set) var mills: [Mill] = []
    private(set) var yards: [Yard] = []

    init() {
        loadMills()
        loadYards()
    }

    private func loadMills() {
        guard let url = Bundle.main.url(forResource: "mills", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load mills.json from bundle")
            return
        }
        do {
            mills = try JSONDecoder().decode([Mill].self, from: data)
                .sorted { $0.name < $1.name }
            print("Loaded \(mills.count) mills")
        } catch {
            print("Failed to decode mills.json: \(error)")
        }
    }

    private func loadYards() {
        guard let url = Bundle.main.url(forResource: "yards", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load yards.json from bundle")
            return
        }
        do {
            yards = try JSONDecoder().decode([Yard].self, from: data)
                .sorted { ($0.state, $0.city) < ($1.state, $1.city) }
            print("Loaded \(yards.count) yards")
        } catch {
            print("Failed to decode yards.json: \(error)")
        }
    }

    // MARK: - Search & Filter

    func searchMills(_ query: String) -> [Mill] {
        guard !query.isEmpty else { return mills }
        let q = query.lowercased()
        return mills.filter {
            $0.name.lowercased().contains(q) ||
            $0.city.lowercased().contains(q) ||
            $0.state.lowercased().contains(q) ||
            $0.vendor.lowercased().contains(q) ||
            $0.product.lowercased().contains(q)
        }
    }

    func searchYards(_ query: String) -> [Yard] {
        guard !query.isEmpty else { return yards }
        let q = query.lowercased()
        return yards.filter {
            $0.posNumber.contains(q) ||
            $0.city.lowercased().contains(q) ||
            $0.state.lowercased().contains(q) ||
            $0.market.lowercased().contains(q) ||
            $0.manager.lowercased().contains(q) ||
            $0.storeNumber.contains(q)
        }
    }

    func mills(forProduct product: Mill.ProductType) -> [Mill] {
        mills.filter { $0.productType == product }
    }

    func yards(inState state: String) -> [Yard] {
        yards.filter { $0.state.uppercased() == state.uppercased() }
    }

    func yards(inMarket market: String) -> [Yard] {
        yards.filter { $0.market == market }
    }

    var uniqueMarkets: [String] {
        Array(Set(yards.map(\.market))).sorted()
    }

    var uniqueYardStates: [String] {
        Array(Set(yards.map(\.state))).sorted()
    }

    /// Unique yards by coordinate (for batch deduplication).
    /// Multiple stores at the same address share coordinates.
    var uniqueYardsByLocation: [Yard] {
        var seen = Set<String>()
        return yards.filter { yard in
            let key = "\(String(format: "%.4f", yard.lat)),\(String(format: "%.4f", yard.lon))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
