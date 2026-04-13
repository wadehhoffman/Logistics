import Foundation
import SwiftUI

/// Reference data store for Mills and Yards.
///
/// Loading order (Phase iB):
///   1. On init — load from on-disk cache in Application Support if it exists,
///      otherwise fall back to the bundled seed JSON. Synchronous, fast.
///   2. After init — caller invokes `refresh(serverBaseURL:)` (typically from
///      a `.task` on the root view) to fetch the latest from the server and
///      overwrite the cache. Background, async.
///
/// This means the app starts instantly with whatever data we have and silently
/// upgrades to fresh data once the network responds. If the server is unreachable,
/// the cache continues to serve.
@Observable
final class LocationDataStore {
    private(set) var mills: [Mill] = []
    private(set) var yards: [Yard] = []
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing: Bool = false
    private(set) var lastSyncError: String?

    init() {
        loadMills()
        loadYards()
    }

    // MARK: - Load (cache first, bundle fallback)

    private func loadMills() {
        if let cached = readCache(filename: "mills.cache.json") {
            do {
                mills = try JSONDecoder().decode([Mill].self, from: cached)
                    .sorted { $0.name < $1.name }
                print("[Data] Loaded \(mills.count) mills from cache")
                return
            } catch {
                print("[Data] mills.cache.json failed to decode (\(error)), falling back to bundle")
            }
        }
        // Bundle seed
        guard let url = Bundle.main.url(forResource: "mills", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[Data] Failed to load mills.json from bundle")
            return
        }
        do {
            mills = try JSONDecoder().decode([Mill].self, from: data)
                .sorted { $0.name < $1.name }
            print("[Data] Loaded \(mills.count) mills from bundle seed")
        } catch {
            print("[Data] Failed to decode bundled mills.json: \(error)")
        }
    }

    private func loadYards() {
        if let cached = readCache(filename: "yards.cache.json") {
            do {
                yards = try JSONDecoder().decode([Yard].self, from: cached)
                    .sorted { ($0.state, $0.city) < ($1.state, $1.city) }
                print("[Data] Loaded \(yards.count) yards from cache")
                return
            } catch {
                print("[Data] yards.cache.json failed to decode (\(error)), falling back to bundle")
            }
        }
        guard let url = Bundle.main.url(forResource: "yards", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[Data] Failed to load yards.json from bundle")
            return
        }
        do {
            yards = try JSONDecoder().decode([Yard].self, from: data)
                .sorted { ($0.state, $0.city) < ($1.state, $1.city) }
            print("[Data] Loaded \(yards.count) yards from bundle seed")
        } catch {
            print("[Data] Failed to decode bundled yards.json: \(error)")
        }
    }

    // MARK: - Refresh from server

    /// Fetch the latest Mills and Yards from the server, update the in-memory
    /// arrays, and write the result to the on-disk cache. Both succeed-or-fail
    /// independently; partial success is fine (e.g. mills updates, yards fails).
    @MainActor
    func refresh(serverBaseURL: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        let service = MillsYardsService(baseURL: serverBaseURL)

        async let millsTask = Self.fetchAndCache(
            label: "Mills",
            cacheFile: "mills.cache.json",
            fetch: { try await service.fetchMills() }
        )
        async let yardsTask = Self.fetchAndCache(
            label: "Yards",
            cacheFile: "yards.cache.json",
            fetch: { try await service.fetchYards() }
        )

        let (newMills, newYards) = await (millsTask, yardsTask)
        var errors: [String] = []
        if let newMills { self.mills = newMills.sorted { $0.name < $1.name } }
        else { errors.append("mills") }
        if let newYards { self.yards = newYards.sorted { ($0.state, $0.city) < ($1.state, $1.city) } }
        else { errors.append("yards") }

        if errors.isEmpty {
            self.lastSyncedAt = Date()
        } else {
            self.lastSyncError = "Could not refresh: \(errors.joined(separator: ", "))"
        }
    }

    /// Run the fetch + cache write off the main actor. Returns nil on any failure.
    private static func fetchAndCache<T: Codable>(
        label: String,
        cacheFile: String,
        fetch: @Sendable () async throws -> [T]
    ) async -> [T]? {
        do {
            let items = try await fetch()
            // Persist atomically — if encode/write fails, in-memory data still updates
            do {
                let data = try JSONEncoder().encode(items)
                try writeCache(filename: cacheFile, data: data)
                print("[Data] Refreshed \(items.count) \(label.lowercased()) from server, cached")
            } catch {
                print("[Data] Cache write failed for \(cacheFile): \(error)")
            }
            return items
        } catch {
            print("[Data] \(label) refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Cache file IO (Application Support)

    private static var cacheDirectoryURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("ReferenceData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func readCache(filename: String) -> Data? {
        guard let url = Self.cacheDirectoryURL?.appendingPathComponent(filename),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func writeCache(filename: String, data: Data) throws {
        guard let url = cacheDirectoryURL?.appendingPathComponent(filename) else {
            throw NSError(domain: "LocationDataStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "No cache directory"])
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Search & Filter (unchanged from prior version)

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
