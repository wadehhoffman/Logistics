import Foundation

struct ScheduledRoute: Identifiable {
    let id: String
    let createdAt: String
    let scheduledAt: String
    let type: String             // "single" or "truck"
    let mill: ScheduleMill?
    let yard: ScheduleYard?
    var truck: ScheduleTruck?
    let distance: String?
    let duration: Double?
    var notes: String
    var status: String           // raw string; use `statusEnum` for typed access
    let hosProjection: HOSProjection?

    enum Status: String, Codable {
        case scheduled
        case inProgress  = "in-progress"
        case delivered
        case cancelled
        case completed              // legacy — server may still emit this for older entries
    }

    var statusEnum: Status { Status(rawValue: status) ?? .scheduled }

    var scheduledDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.date(from: scheduledAt) ?? {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return df.date(from: scheduledAt)
        }()
    }

    var dateString: String {
        guard let date = scheduledDate else { return scheduledAt.split(separator: "T").first.map(String.init) ?? "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    var timeString: String {
        guard let date = scheduledDate else { return "—" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    var dayKey: String {
        // "2026-04-15"
        String(scheduledAt.prefix(10))
    }

    var statusColor: String {
        switch statusEnum {
        case .delivered, .completed: return "green"
        case .inProgress:            return "orange"
        case .cancelled:             return "gray"
        case .scheduled:             return "blue"
        }
    }

    /// True if this route's HOS projection requires an overnight 10-hour rest mid-trip
    var requiresOvernightRest: Bool {
        hosProjection?.segments.contains(where: { $0.type == .rest }) ?? false
    }

    /// True if HOS rules can't be satisfied (weekly cap hit, etc.)
    var hasHosViolations: Bool {
        !(hosProjection?.violations.isEmpty ?? true)
    }
}

struct ScheduleMill: Codable {
    let name: String
    let vendor: String?
    let city: String?
    let state: String?
    let uuid: String?

    init(name: String, vendor: String? = nil, city: String? = nil, state: String? = nil, uuid: String? = nil) {
        self.name = name; self.vendor = vendor; self.city = city; self.state = state; self.uuid = uuid
    }
}

struct ScheduleYard: Codable {
    let posNumber: String?
    let city: String?
    let state: String?
    let uuid: String?

    init(posNumber: String? = nil, city: String? = nil, state: String? = nil, uuid: String? = nil) {
        self.posNumber = posNumber; self.city = city; self.state = state; self.uuid = uuid
    }
}

struct ScheduleTruck: Codable {
    let id: String?
    let name: String
    let driver: String?
    let `operator`: String?

    init(id: String?, name: String, driver: String?, operator: String? = nil) {
        self.id = id
        self.name = name
        self.driver = driver
        self.`operator` = `operator`
    }

    /// Best display for the assigned person — operator first, fall back to driver
    var operatorOrDriver: String {
        let op = (self.`operator` ?? "").trimmingCharacters(in: .whitespaces)
        if !op.isEmpty { return op }
        return driver ?? ""
    }
}

// MARK: - DOT Hours-of-Service projection (server-attached on /api/schedule POST)

struct HOSProjection: Codable {
    let segments: [HOSSegment]
    let deliveryEta: String
    let totalElapsedSec: Double
    let drivingSec: Double
    let breakSec: Double
    let restSec: Double
    let weekHoursAtEnd: Double
    let violations: [HOSViolation]
}

struct HOSSegment: Codable, Identifiable {
    let id = UUID()
    let type: SegmentType
    let start: String
    let end: String
    let durationSec: Double
    let reason: String?
    let cumulativeDriveHours: Double?

    enum SegmentType: String, Codable {
        case drive, `break`, rest
    }

    enum CodingKeys: String, CodingKey {
        case type, start, end, durationSec, reason, cumulativeDriveHours
    }
}

struct HOSViolation: Codable, Identifiable {
    let id = UUID()
    let type: String
    let message: String
    let atSegment: Int?

    enum CodingKeys: String, CodingKey {
        case type, message, atSegment
    }
}

// Custom Codable for ScheduledRoute to handle flexible server JSON
extension ScheduledRoute: Codable {
    enum CodingKeys: String, CodingKey {
        case id, createdAt, scheduledAt, type, mill, yard, truck, distance, duration, notes, status
        case hosProjection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        scheduledAt = try c.decodeIfPresent(String.self, forKey: .scheduledAt) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "single"
        mill = try c.decodeIfPresent(ScheduleMill.self, forKey: .mill)
        yard = try c.decodeIfPresent(ScheduleYard.self, forKey: .yard)
        truck = try c.decodeIfPresent(ScheduleTruck.self, forKey: .truck)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "scheduled"
        hosProjection = try c.decodeIfPresent(HOSProjection.self, forKey: .hosProjection)

        // distance can be String or Number
        if let s = try? c.decode(String.self, forKey: .distance) { distance = s }
        else if let d = try? c.decode(Double.self, forKey: .distance) { distance = String(format: "%.1f mi", d) }
        else { distance = nil }

        if let d = try? c.decode(Double.self, forKey: .duration) { duration = d }
        else if let i = try? c.decode(Int.self, forKey: .duration) { duration = Double(i) }
        else { duration = nil }
    }
}

struct ScheduleListResponse: Codable {
    let schedules: [ScheduledRoute]
    let total: Int
}
