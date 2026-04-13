import Foundation

/// Audit-log entry written by the server whenever a mill, yard, or schedule
/// is created / updated / deleted. Matches the shape returned by
/// GET /api/activity?limit=N&offset=N.
struct ActivityEvent: Codable, Identifiable {
    let id: String
    let timestamp: String
    let ip: String
    let user: String?          // populated once SSO lands; nil for now
    let action: Action
    let entity: Entity
    /// Free-form details payload. Server sends a small object per event
    /// (names, changes diff, etc). Decoded lazily as needed via `detailsText`.
    let details: DetailsValue?

    enum Action: String, Codable {
        case create, update, delete, login, logout
    }

    enum Entity: String, Codable {
        case mill, yard, schedule, auth
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Entity(rawValue: raw) ?? .unknown
        }
    }

    /// Best-effort parsed Date from the ISO8601 timestamp the server writes
    var date: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }

    /// Short "2h ago"-style label
    var relativeTime: String {
        guard let d = date else { return timestamp }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }

    /// Pretty-printed details for display in the expanded UI row.
    var detailsText: String {
        guard let details, let obj = details.object else { return "" }
        let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// The server's `details` payload is a heterogeneous object. We capture it
/// as an opaque container so we can render it without forcing a schema.
struct DetailsValue: Codable {
    /// Underlying JSON object if present
    let object: [String: Any]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode(JSONAny.self) {
            self.object = dict.value as? [String: Any]
        } else {
            self.object = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        // Activity is read-only on the client; server writes always. Encode as empty.
        var container = encoder.singleValueContainer()
        try container.encode([String: String]())
    }
}

/// Minimal "any JSON value" decoder — only used inside DetailsValue.
private struct JSONAny: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)       { value = v; return }
        if let v = try? c.decode(Int.self)        { value = v; return }
        if let v = try? c.decode(Double.self)     { value = v; return }
        if let v = try? c.decode(String.self)     { value = v; return }
        if let v = try? c.decode([JSONAny].self)  { value = v.map(\.value); return }
        if let v = try? c.decode([String: JSONAny].self) { value = v.mapValues(\.value); return }
        if c.decodeNil() { value = NSNull(); return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encodeNil()
    }
}

/// Wraps /api/activity response shape: `{ "events": [...], "total": N, "offset": N, "limit": N }`
struct ActivityListResponse: Codable {
    let events: [ActivityEvent]
    let total: Int
    let offset: Int
    let limit: Int
}
