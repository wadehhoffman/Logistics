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
    var status: String           // "scheduled", "completed", "cancelled"

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
        switch status {
        case "completed": return "green"
        case "cancelled": return "gray"
        default: return "blue"
        }
    }
}

struct ScheduleMill: Codable {
    let name: String
    let vendor: String?
    let city: String?
    let state: String?
}

struct ScheduleYard: Codable {
    let posNumber: String?
    let city: String?
    let state: String?
}

struct ScheduleTruck: Codable {
    let id: String?
    let name: String
    let driver: String?
}

// Custom Codable for ScheduledRoute to handle flexible server JSON
extension ScheduledRoute: Codable {
    enum CodingKeys: String, CodingKey {
        case id, createdAt, scheduledAt, type, mill, yard, truck, distance, duration, notes, status
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
