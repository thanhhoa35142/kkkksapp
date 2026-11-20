import Foundation

// MARK: - Getaways

extension APIClient {
    /// `GET /v1/getaways?start=&days=&limit=` — cities ranked by picnic
    /// weather over `days` calendar days from `start`. The server applies
    /// `start` in each city's time zone and clamps `limit` to 3 on Free.
    func getaways(start: CivilDay, days: Int, limit: Int) async throws -> GetawayList {
        let items = [
            URLQueryItem(name: "start", value: start.string),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await get("/v1/getaways", query: items, enveloped: true)
    }
}
