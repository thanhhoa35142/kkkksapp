import Foundation

/// Maps API reason codes (`{code, params}`) to localized display strings.
/// The server never sends translated text — this is the single place that
/// turns codes into UI copy. Unknown codes fall back to the raw code so a new
/// server reason never crashes or renders blank.
///
/// Catalog source: backend/internal/modules/scoring/scorer.go.
enum ReasonLocalizer {
    static func text(for reason: Reason) -> String {
        text(code: reason.code, params: reason.params)
    }

    static func text(code: String, params: [String: JSONValue]?) -> String {
        switch code {
        // Weather
        case "weather.clear":
            return String(localized: "Clear skies, \(temp(params))°")
        case "weather.rain_risk":
            return String(localized: "Rain likely, \(prob(params))% chance")
        case "weather.hot":
            return String(localized: "Hot, \(temp(params))°")
        case "weather.cold":
            return String(localized: "Cold, \(temp(params))°")
        case "weather.cloudy":
            return String(localized: "Overcast")

        // Crowd
        case "crowd.low":
            return String(localized: "Quiet right now")
        case "crowd.moderate":
            return String(localized: "Some people around")
        case "crowd.high":
            return String(localized: "Busy right now")

        // Amenities / freshness
        case "amenity.well_equipped":
            return String(localized: "Good facilities nearby")
        case "fresh.recent":
            return String(localized: "Recently verified")

        // Hard caps — these explain a low score, order matters in UI
        case "cap.rain":
            return String(localized: "Rain expected — score capped")
        case "cap.heat":
            return String(localized: "Extreme heat — score capped")
        case "cap.cold":
            return String(localized: "Freezing — score capped")

        default:
            return code
        }
    }

    // MARK: - Param helpers

    private static func param(_ params: [String: JSONValue]?, _ key: String) -> Double? {
        if case .number(let n)? = params?[key] { return n }
        return nil
    }

    /// `temp` arrives rounded to 0.1 — display as whole degrees.
    private static func temp(_ params: [String: JSONValue]?) -> String {
        guard let t = param(params, "temp") else { return "--" }
        return String(Int(t.rounded()))
    }

    /// `prob` is a 0–100 percentage already.
    private static func prob(_ params: [String: JSONValue]?) -> String {
        guard let p = param(params, "prob") else { return "--" }
        return String(Int(p.rounded()))
    }
}
