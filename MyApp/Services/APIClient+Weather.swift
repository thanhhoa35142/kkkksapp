import Foundation

// MARK: - Weather

extension APIClient {
    /// `GET /v1/weather/nearby?lat=&lng=` — hourly forecast for the next 48 h
    /// at a coordinate. Note `lng` (recommendations use `lon`).
    func nearbyWeather(lat: Double, lng: Double) async throws -> [NearbyWeatherPoint] {
        let items = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]
        return try await get("/v1/weather/nearby", query: items, enveloped: true)
    }
}
