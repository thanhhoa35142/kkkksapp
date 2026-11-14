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
            return String(localized: "Clear skies, \(temp(params))")
        case "weather.rain_risk":
            return String(localized: "Rain likely, \(prob(params))% chance")
        case "weather.hot":
            return String(localized: "Hot, \(temp(params))")
        case "weather.cold":
            return String(localized: "Cold, \(temp(params))")
        case "weather.cloudy":
            return String(localized: "Overcast")

        // Crowd — time-neutral: the viewed hour may be later today or
        // another day, and crowd levels are an estimate (UI_SPEC §16).
        case "crowd.low":
            return String(localized: "Usually quiet at this hour")
        case "crowd.moderate":
            return String(localized: "Some people around")
        case "crowd.high":
            return String(localized: "Usually busy at this hour")

        // Amenities / freshness
        case "amenity.well_equipped":
            return String(localized: "Good facilities nearby")
        case "fresh.recent":
            return String(localized: "Recently verified")

        // Hard caps — these explain a low score, order matters in UI
        case "cap.rain":
            return String(localized: "Rain expected, score capped")
        case "cap.heat":
            return String(localized: "Extreme heat, score capped")
        case "cap.cold":
            return String(localized: "Freezing, score capped")
        case "cap.dark":
            return String(localized: "After dark, score capped")
        case "cap.twilight":
            return String(localized: "Dusk or dawn, score capped")

        default:
            // Unknown codes are dropped by callers via `isKnown` — never shown raw.
            return code
        }
    }

    /// Codes this build can phrase; newer server codes are skipped in UI.
    static func isKnown(_ code: String) -> Bool {
        symbol(for: code) != nil
    }

    /// SF Symbol for a reason row (Spot Detail). nil = unknown code.
    static func symbol(for code: String) -> String? {
        switch code {
        case "weather.clear": "sun.max.fill"
        case "weather.rain_risk": "cloud.rain.fill"
        case "weather.hot": "thermometer.sun.fill"
        case "weather.cold": "thermometer.snowflake"
        case "weather.cloudy": "cloud.fill"
        case "crowd.low", "crowd.moderate", "crowd.high": "person.2.fill"
        case "amenity.well_equipped": "toilet.fill"
        case "fresh.recent": "checkmark.seal.fill"
        case "cap.rain": "cloud.heavyrain.fill"
        case "cap.heat": "thermometer.sun.fill"
        case "cap.cold": "snowflake"
        case "cap.dark": "moon.fill"
        case "cap.twilight": "sun.horizon.fill"
        default: nil
        }
    }

    // MARK: - Param helpers

    private static func param(_ params: [String: JSONValue]?, _ key: String) -> Double? {
        if case .number(let n)? = params?[key] { return n }
        return nil
    }

    /// `temp` arrives in °C rounded to 0.1 — formatted per unit preference.
    private static func temp(_ params: [String: JSONValue]?) -> String {
        guard let t = param(params, "temp") else { return "--" }
        return Format.temperature(celsius: t)
    }

    /// `prob` is a 0–100 percentage already.
    private static func prob(_ params: [String: JSONValue]?) -> String {
        guard let p = param(params, "prob") else { return "--" }
        return String(Int(p.rounded()))
    }
}
