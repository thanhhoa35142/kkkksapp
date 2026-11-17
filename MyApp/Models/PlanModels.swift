import Foundation


struct ServerPlan: Decodable, Identifiable, Equatable {
    let id: UUID
    /// "owner" | "follower"
    let role: String
    /// "upcoming" | "started" | "ended" | "canceled"
    let status: String
    let shareToken: String
    let spot: PlanSpotRef
    let start: Date
    let end: Date
    let tz: String
    /// "ok" | "worse" | "bad"; nil before the first evaluation.
    let state: String?
    let score: Int?
    let capReason: String?
    /// nil while the plan is `ok`.
    let alternative: PlanAlternative?
    let createdAt: Date?
    /// Owner only.
    let baselineScore: Int?
    let followerCount: Int?

    var isOwner: Bool { role == "owner" }
    var isFollower: Bool { role == "follower" }
    /// Not canceled and not ended.
    var isActive: Bool { status == "upcoming" || status == "started" }
    var planStatus: PlanStatus? { PlanStatus(serverState: state) }
    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// For rows and labels; `score` 0 when the server has none yet.
    var window: PlanWindow {
        PlanWindow(spotID: spot.id, spotName: spot.displayName, timeZone: timeZone,
                   start: start, end: end, score: score ?? 0)
    }
}

struct PlanSpotRef: Decodable, Equatable {
    let id: UUID
    /// Empty for unnamed spots.
    let name: String?
    let kind: String?

    /// The name, or the kind ("Park") for unnamed spots.
    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        return KindStyle.label(kind ?? "")
    }
}


struct PlanAlternative: Decodable, Equatable {
    let type: String
    let start: Date?
    let end: Date?
    let spotId: UUID?
    let spotName: String?
    let spotKind: String?
    let score: Int?
}

struct ServerPlanList: Decodable {
    let items: [ServerPlan]
}

/// `POST /v1/plans` body. Times go out as RFC 3339 (APIClient's encoder).
struct PlanCreateRequest: Encodable {
    let spotId: UUID
    let start: Date
    let end: Date
    let tz: String
}

/// `GET /v1/shared-plans/{token}` — the anonymous token view: one window,
/// no plan id, owner, followers or alternative.
struct SharedPlan: Decodable {
    let spot: PlanSpotRef
    let start: Date
    let end: Date
    let tz: String
    let state: String?
    let score: Int?
    let capReason: String?
    /// Codes of the window's worst hour (at most 3).
    let reasons: [Reason]?

    var planStatus: PlanStatus? { PlanStatus(serverState: state) }
    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
    var window: PlanWindow {
        PlanWindow(spotID: spot.id, spotName: spot.displayName, timeZone: timeZone,
                   start: start, end: end, score: score ?? 0)
    }
}

/// Body-less POST (`/v1/plan-follows/{token}`): the server reads no body.
struct EmptyBody: Encodable {}

extension PlanStatus {
    /// Server `state` → the app's three statuses (same thresholds: worse =
    /// 15 below the baseline; bad = rain/heat/cold or under 60).
    init?(serverState: String?) {
        switch serverState {
        case "ok": self = .good
        case "worse": self = .worse
        case "bad": self = .notRecommended
        default: return nil
        }
    }
}
