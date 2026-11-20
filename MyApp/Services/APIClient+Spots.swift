import Foundation

// MARK: - Spots (map)

extension APIClient {
    /// `GET /v1/spots?bbox=` — GeoJSON FeatureCollection (not enveloped).
    /// - `from` + `hours`: adds `properties.scores` for the map time-lapse.
    /// - `includeArea`: adds simplified `properties.area` outlines (zoomed in).
    func spots(bbox: String, when: Date? = nil, from: Date? = nil, hours: Int? = nil,
               includeArea: Bool = false, filters: SpotFilters = SpotFilters()) async throws -> SpotFeatureCollection {
        var items = [URLQueryItem(name: "bbox", value: bbox)]
        items += Self.timeQuery(when: when, from: from, hours: hours)
        if includeArea { items.append(URLQueryItem(name: "include", value: "area")) }
        items += filters.queryItems
        return try await get("/v1/spots", query: items, enveloped: false)
    }

    /// `GET /v1/spots?ids=` — batch lookup for saved spots (≤ 50 ids).
    /// - `from` + `hours` (1…24): adds `properties.scores`, e.g. Best Now's
    ///   "Good until 6 PM" line. Callers clamp `hours` to the plan (`HourWindow`).
    func spots(ids: [UUID], when: Date? = nil, from: Date? = nil, hours: Int? = nil) async throws -> SpotFeatureCollection {
        let joined = ids.prefix(50).map(\.uuidString).joined(separator: ",")
        var items = [URLQueryItem(name: "ids", value: joined)]
        items += Self.timeQuery(when: when, from: from, hours: hours)
        return try await get("/v1/spots", query: items, enveloped: false)
    }

    /// `GET /v1/spots/{id}`
    func spot(id: UUID) async throws -> SpotDetail {
        try await get("/v1/spots/\(id.uuidString)", enveloped: true)
    }

    /// `GET /v1/spots/{id}/forecast` — 7 days × 24h.
    func forecast(spotID: UUID) async throws -> [ForecastPoint] {
        try await get("/v1/spots/\(spotID.uuidString)/forecast", enveloped: true)
    }

    /// `GET /v1/packs` — cities with data.
    func packs() async throws -> [CityPack] {
        let list: CityPackList = try await get("/v1/packs", enveloped: true)
        return list.items
    }

    private static func timeQuery(when: Date?, from: Date?, hours: Int?) -> [URLQueryItem] {
        let iso = ISO8601DateFormatter()
        var items: [URLQueryItem] = []
        if let when { items.append(URLQueryItem(name: "when", value: iso.string(from: when))) }
        if let from { items.append(URLQueryItem(name: "from", value: iso.string(from: from))) }
        if let hours { items.append(URLQueryItem(name: "hours", value: String(hours))) }
        return items
    }
}
