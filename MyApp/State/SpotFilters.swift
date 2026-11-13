import Foundation

/// S8 · Filters, applied server-side (`kinds`, `amenities`, `minScore` on
/// /v1/recommendations and /v1/spots) so the Free 3-pick limit still returns
/// matching spots.
struct SpotFilters: Codable, Equatable, Hashable {
    static let allKinds = ["park", "beach", "site", "table"]
    static let filterableAmenities = ["toilet", "water", "bbq", "playground", "shelter", "dog_area"]
    static let minScoreOptions = [40, 60, 80]

    /// Empty = every kind.
    var kinds: Set<String> = []
    /// Spot must have all of these.
    var amenities: Set<String> = []
    var minScore: Int?

    var isActive: Bool { !kinds.isEmpty || !amenities.isEmpty || minScore != nil }

    var activeCount: Int {
        (kinds.isEmpty ? 0 : 1) + amenities.count + (minScore == nil ? 0 : 1)
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !kinds.isEmpty {
            items.append(URLQueryItem(name: "kinds", value: kinds.sorted().joined(separator: ",")))
        }
        if !amenities.isEmpty {
            items.append(URLQueryItem(name: "amenities", value: amenities.sorted().joined(separator: ",")))
        }
        if let minScore {
            items.append(URLQueryItem(name: "minScore", value: String(minScore)))
        }
        return items
    }
}
