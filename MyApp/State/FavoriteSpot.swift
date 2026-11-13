import Foundation
import SwiftData

/// Saved spot, stored on device (spec F5). Free plan: up to 10.
@Model
final class FavoriteSpot {
    @Attribute(.unique) var spotID: UUID
    var name: String
    var kind: String
    var city: String?
    var tz: String
    var latitude: Double?
    var longitude: Double?
    /// User order in Saved (drag to reorder).
    var sortIndex: Int
    var addedAt: Date

    init(summary: SpotSummary, sortIndex: Int) {
        spotID = summary.id
        name = summary.displayName
        kind = summary.kind
        city = summary.city
        tz = summary.tz
        latitude = summary.latitude
        longitude = summary.longitude
        self.sortIndex = sortIndex
        addedAt = .now
    }
}

enum Favorites {
    static let freeLimit = 10

    /// Adds or removes. Returns false when the Free limit blocks adding
    /// (caller shows the paywall).
    @MainActor
    @discardableResult
    static func toggle(_ summary: SpotSummary, existing: [FavoriteSpot],
                       isPlus: Bool, context: ModelContext) -> Bool {
        if let match = existing.first(where: { $0.spotID == summary.id }) {
            context.delete(match)
            return true
        }
        guard isPlus || existing.count < freeLimit else { return false }
        let next = (existing.map(\.sortIndex).max() ?? -1) + 1
        context.insert(FavoriteSpot(summary: summary, sortIndex: next))
        return true
    }
}
