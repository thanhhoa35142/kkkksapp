import Foundation
import Observation

/// Routes notification taps to in-app destinations. Views observe
/// `pendingSpotID` and clear it after navigating.
@MainActor @Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Spot the user tapped a notification for — consumed once by the map.
    var pendingSpotID: UUID?

    private init() {}

    func handle(spotID: UUID?) {
        pendingSpotID = spotID
    }

    func consume() -> UUID? {
        defer { pendingSpotID = nil }
        return pendingSpotID
    }
}
