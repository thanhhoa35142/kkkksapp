import Foundation

// MARK: - Recommendations

extension APIClient {
    /// `GET /v1/recommendations?lat=&lon=&radius=&when=&limit=`
    func recommendations(lat: Double, lon: Double, radiusM: Double? = nil, when: Date? = nil, limit: Int? = nil,
                         filters: SpotFilters = SpotFilters()) async throws -> RecommendationList {
        var items = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
        ]
        if let radiusM { items.append(URLQueryItem(name: "radius", value: String(radiusM))) }
        if let when { items.append(URLQueryItem(name: "when", value: ISO8601DateFormatter().string(from: when))) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        items += filters.queryItems
        return try await get("/v1/recommendations", query: items, enveloped: true)
    }
}
