import Foundation

actor ScheduleService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - List

    func fetchSchedules(month: String? = nil) async throws -> [ScheduledRoute] {
        var urlStr = "\(baseURL)/api/schedule"
        if let month = month { urlStr += "?month=\(month)" }
        guard let url = URL(string: urlStr) else { throw ScheduleError.invalidURL }

        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScheduleError.networkError
        }
        let result = try JSONDecoder().decode(ScheduleListResponse.self, from: data)
        return result.schedules
    }

    // MARK: - Create

    func createSchedule(_ payload: CreateSchedulePayload) async throws -> ScheduledRoute {
        guard let url = URL(string: "\(baseURL)/api/schedule") else { throw ScheduleError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw ScheduleError.createFailed
        }
        return try JSONDecoder().decode(ScheduledRoute.self, from: data)
    }

    // MARK: - Update

    func updateSchedule(id: String, status: String? = nil, notes: String? = nil, truck: ScheduleTruck? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/api/schedule/\(id)") else { throw ScheduleError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let status { body["status"] = status }
        if let notes { body["notes"] = notes }
        if let truck { body["truck"] = ["id": truck.id ?? "", "name": truck.name, "driver": truck.driver ?? ""] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScheduleError.updateFailed
        }
    }

    // MARK: - Delete

    func deleteSchedule(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/schedule/\(id)") else { throw ScheduleError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScheduleError.deleteFailed
        }
    }

    enum ScheduleError: Error, LocalizedError {
        case invalidURL, networkError, createFailed, updateFailed, deleteFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid server URL"
            case .networkError: return "Could not reach schedule server"
            case .createFailed: return "Failed to create schedule"
            case .updateFailed: return "Failed to update schedule"
            case .deleteFailed: return "Failed to delete schedule"
            }
        }
    }
}

struct CreateSchedulePayload: Codable {
    let scheduledAt: String
    let type: String
    let mill: ScheduleMill?
    let yard: ScheduleYard?
    let truck: ScheduleTruck?
    let distance: String?
    let duration: Double?
    let fuelCost: Double?
    let notes: String
}
