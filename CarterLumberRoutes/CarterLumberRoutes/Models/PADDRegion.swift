import Foundation

enum PADDRegion: String, CaseIterable {
    case newEngland = "R1X"
    case centralAtlantic = "R1Y"
    case lowerAtlantic = "R1Z"
    case midwest = "R20"
    case gulfCoast = "R30"
    case rockyMountain = "R40"
    case westCoast = "R50"

    var displayName: String {
        switch self {
        case .newEngland: return "New England"
        case .centralAtlantic: return "Central Atlantic"
        case .lowerAtlantic: return "Lower Atlantic"
        case .midwest: return "Midwest"
        case .gulfCoast: return "Gulf Coast"
        case .rockyMountain: return "Rocky Mountain"
        case .westCoast: return "West Coast"
        }
    }

    static let stateToPADD: [String: PADDRegion] = [
        // PADD 1A - New England
        "CT": .newEngland, "ME": .newEngland, "MA": .newEngland,
        "NH": .newEngland, "RI": .newEngland, "VT": .newEngland,
        // PADD 1B - Central Atlantic
        "DE": .centralAtlantic, "DC": .centralAtlantic, "MD": .centralAtlantic,
        "NJ": .centralAtlantic, "NY": .centralAtlantic, "PA": .centralAtlantic,
        // PADD 1C - Lower Atlantic
        "FL": .lowerAtlantic, "GA": .lowerAtlantic, "NC": .lowerAtlantic,
        "SC": .lowerAtlantic, "VA": .lowerAtlantic, "WV": .lowerAtlantic,
        // PADD 2 - Midwest
        "IL": .midwest, "IN": .midwest, "IA": .midwest, "KS": .midwest,
        "KY": .midwest, "MI": .midwest, "MN": .midwest, "MO": .midwest,
        "NE": .midwest, "ND": .midwest, "OH": .midwest, "OK": .midwest,
        "SD": .midwest, "TN": .midwest, "WI": .midwest,
        // PADD 3 - Gulf Coast
        "AL": .gulfCoast, "AR": .gulfCoast, "LA": .gulfCoast,
        "MS": .gulfCoast, "NM": .gulfCoast, "TX": .gulfCoast,
        // PADD 4 - Rocky Mountain
        "CO": .rockyMountain, "ID": .rockyMountain, "MT": .rockyMountain,
        "UT": .rockyMountain, "WY": .rockyMountain,
        // PADD 5 - West Coast
        "AK": .westCoast, "AZ": .westCoast, "CA": .westCoast,
        "HI": .westCoast, "NV": .westCoast, "OR": .westCoast, "WA": .westCoast,
    ]

    static func region(for stateCode: String) -> PADDRegion? {
        stateToPADD[stateCode.uppercased()]
    }
}
