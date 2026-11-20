import Foundation
import Observation

/// Routes notification taps to in-app destinations. Views observe
/// `pendingSpotID` / `pendingPlan` and clear them after navigating.
@MainActor @Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// Spot the user tapped a notification for — consumed once by the map.
    var pendingSpotID: UUID?
    /// Plan push tapped — consumed once by the root, which can tell the
    /// user's own plan (by server id) from a followed one (by token).
    var pendingPlan: PlanPushTarget?
    /// Hour to open `pendingSpotID` at (good-day push: the best window's
    /// start). Consumed together with the spot by the root, which checks it
    /// is still usable (not past, within the plan's horizon).
    var pendingHour: Date?

    private init() {}

    func handle(spotID: UUID?) {
        pendingSpotID = spotID
        pendingHour = nil
    }

    /// Hour first, so the root finds it when the spot change arrives.
    func handle(spotID: UUID, hour: Date) {
        pendingHour = hour
        pendingSpotID = spotID
    }

    func consumeHour() -> Date? {
        defer { pendingHour = nil }
        return pendingHour
    }

    func consume() -> UUID? {
        defer { pendingSpotID = nil }
        return pendingSpotID
    }

    func handle(plan: PlanPushTarget) {
        pendingPlan = plan
    }

    func consumePlan() -> PlanPushTarget? {
        defer { pendingPlan = nil }
        return pendingPlan
    }
}

/// What a `plan.changed` / `plan.confirmed` tap opens. The same payload goes
/// to the owner and every follower: the owner matches `planID` to a local
/// plan, a follower opens the shared view by `shareToken`.
struct PlanPushTarget: Equatable, Sendable {
    let planID: UUID?
    let shareToken: String?
    /// "changed" | "confirmed" — the only analytics prop.
    let kind: String
}

/// Notification payload → destination. Pure — unit-tested.
/// Contract: docs/PUSH_KEYS.md (custom fields next to "aps").
enum NotificationRoute: Equatable, Sendable {
    case spot(UUID?)
    /// A spot at its best window's start (`windowStart`), e.g. good-day push.
    case spotAt(UUID, Date)
    case plan(PlanPushTarget)

    static func route(_ userInfo: [AnyHashable: Any]) -> NotificationRoute? {
        guard let kind = userInfo["kind"] as? String else { return nil }
        switch kind {
        case "alert.window", "digest.weekend":
            return .spot((userInfo["spotId"] as? String).flatMap(UUID.init(uuidString:)))
        case "nudge.goodday":
            let spotID = (userInfo["spotId"] as? String).flatMap(UUID.init(uuidString:))
            // Without a usable spot or window it still opens like the digest.
            guard let spotID, let start = (userInfo["windowStart"] as? String).flatMap({ try? APIClient.parseDate($0) }) else {
                return .spot(spotID)
            }
            return .spotAt(spotID, start)
        case "plan.changed", "plan.confirmed":
            let planID = (userInfo["planId"] as? String).flatMap(UUID.init(uuidString:))
            let token = (userInfo["shareToken"] as? String).flatMap { PlanShareLink.isValidToken($0) ? $0 : nil }
            guard planID != nil || token != nil else { return nil }
            return .plan(PlanPushTarget(planID: planID, shareToken: token,
                                        kind: kind == "plan.changed" ? "changed" : "confirmed"))
        default:
            return nil
        }
    }
}
