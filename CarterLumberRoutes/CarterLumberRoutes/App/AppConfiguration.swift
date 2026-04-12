import Foundation
import SwiftUI

@Observable
final class AppConfiguration {
    var mapboxToken: String
    var eiaApiKey: String
    var truckMPG: Double
    var tankSizeGallons: Double
    var intelliShiftBaseURL: String

    private static let mpgKey = "truckMPG"
    private static let tankKey = "tankSizeGallons"
    private static let eiaKey = "eiaApiKey"
    private static let isBaseURLKey = "intelliShiftBaseURL"

    init() {
        // Mapbox token from Info.plist
        self.mapboxToken = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""

        // User-configurable settings from UserDefaults
        let defaults = UserDefaults.standard
        self.truckMPG = defaults.double(forKey: Self.mpgKey) > 0 ? defaults.double(forKey: Self.mpgKey) : 6.5
        self.tankSizeGallons = defaults.double(forKey: Self.tankKey) > 0 ? defaults.double(forKey: Self.tankKey) : 150
        self.eiaApiKey = defaults.string(forKey: Self.eiaKey) ?? "kxKiEkyFtNPI0Fwkh4fG61rBtA3n1F7z6mOMUX06"
        self.intelliShiftBaseURL = defaults.string(forKey: Self.isBaseURLKey) ?? "http://localhost:3003"
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(truckMPG, forKey: Self.mpgKey)
        defaults.set(tankSizeGallons, forKey: Self.tankKey)
        defaults.set(eiaApiKey, forKey: Self.eiaKey)
        defaults.set(intelliShiftBaseURL, forKey: Self.isBaseURLKey)
    }
}
