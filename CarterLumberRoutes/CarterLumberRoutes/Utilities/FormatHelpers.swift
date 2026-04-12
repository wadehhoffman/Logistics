import Foundation

enum FormatHelpers {
    /// Format seconds into a human-readable duration string.
    /// Examples: "3h 24m", "45m", "1h 0m"
    static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Format distance in miles with one decimal place.
    static func formatMiles(_ miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    /// Format distance in km with one decimal place.
    static func formatKm(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    /// Format a dollar amount.
    static func formatCurrency(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    /// Format diesel price per gallon.
    static func formatDieselPrice(_ price: Double) -> String {
        String(format: "$%.3f/gal", price)
    }

    /// State code to full state name.
    static let stateNames: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "Washington DC",
    ]

    static func stateName(for code: String) -> String {
        stateNames[code.uppercased()] ?? code
    }
}
