import Foundation

// MARK: - Spots (map)

extension APIClient {
    /// `GET /v1/spots?bbox=&when=` — GeoJSON FeatureCollection (not enveloped).
    func spots(bbox: String, when: Date? = nil) async throws -> SpotFeatureCollection {
        var items = [URLQueryItem(name: "bbox", value: bbox)]
        if let when { items.append(URLQueryItem(name: "when", value: ISO8601DateFormatter().string(from: when))) }
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
}
