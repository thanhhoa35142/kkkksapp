import Foundation

/// One hour of `GET /v1/weather/nearby` — the forecast for the user's own
/// coordinate, not for a spot. Metric; every value is nil when the provider
/// had none (the server omits the key).
struct NearbyWeatherPoint: Decodable, Identifiable, Equatable {
    let ts: Date
    let tempC: Double?
    let feelsLikeC: Double?
    let precipProb: Int?
    let windKmh: Double?
    let uv: Double?
    let cloud: Int?

    var id: Date { ts }

    /// Something to show in the weather row.
    var hasValues: Bool { tempC != nil || precipProb != nil || windKmh != nil }

    /// SF Symbol for the hour, from rain chance first, then cloud cover.
    var symbolName: String { Self.symbolName(precipProb: precipProb, cloud: cloud) }
}

extension NearbyWeatherPoint {
    static let hourLength: TimeInterval = 3600

    /// The point for `date`: the hour `[ts, ts + 1h)` that contains it, else
    /// the first point at or after it (the list starts after `date`, or has a
    /// gap). nil when the forecast ended before `date` (Plus can pick days
    /// past the 48 h window) — never today's weather labelled as another day.
    nonisolated static func point(at date: Date, in points: [NearbyWeatherPoint]) -> NearbyWeatherPoint? {
        if let containing = points.first(where: { $0.ts <= date && date < $0.ts.addingTimeInterval(hourLength) }) {
            return containing
        }
        return points.filter { $0.ts >= date }.min { $0.ts < $1.ts }
    }

    /// Up to `count` consecutive points starting at the one `point(at:in:)`
    /// picks for `date`.
    nonisolated static func strip(from date: Date, in points: [NearbyWeatherPoint], count: Int = 12) -> [NearbyWeatherPoint] {
        guard let first = point(at: date, in: points),
              let index = points.firstIndex(where: { $0.id == first.id }) else { return [] }
        return Array(points[index...].prefix(count))
    }

    /// True while `now` falls inside the point's hour (labels it "Now").
    nonisolated static func isCurrentHour(_ ts: Date, now: Date = .now) -> Bool {
        ts <= now && now < ts.addingTimeInterval(hourLength)
    }

    /// Simple daytime symbols; the hour row is decorative, so no sunrise/sunset logic.
    nonisolated static func symbolName(precipProb: Int?, cloud: Int?) -> String {
        if let precipProb {
            if precipProb >= 60 { return "cloud.rain" }
            if precipProb >= 30 { return "cloud.drizzle" }
        }
        if let cloud {
            if cloud >= 70 { return "cloud" }
            if cloud >= 30 { return "cloud.sun" }
        }
        return "sun.max"
    }
}
