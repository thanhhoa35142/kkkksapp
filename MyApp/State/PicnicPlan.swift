import Foundation
import Observation
import SwiftData

/// A picnic the user planned: a spot and a time window. Stored on device;
/// sent to the server only when the user turns on forecast alerts for it
/// (C2, `PlanSyncStore`) — then `serverID` is set. Free and Plus alike.
/// Followed plans (someone else's) are never stored here.
///
/// Named `PicnicPlan`, not `Plan`: "plan" already means Free / Plus in
/// Settings and the paywall.
@Model
final class PicnicPlan {
    @Attribute(.unique) var planID: UUID
    var spotID: UUID
    var spotName: String
    var tz: String
    var start: Date
    /// Exclusive, like `PlanWindow.end`.
    var end: Date
    /// Window score when planned — "worse" compares against it.
    var scoreAtSave: Int
    var createdAt: Date

    // MARK: Server sync (C2) — optional / defaulted only, so existing stores
    // migrate without a schema version.

    /// The server plan's id while forecast alerts are on.
    var serverID: UUID? = nil
    /// The share token (`/p/<token>`) while synced. A capability: never log it.
    var shareToken: String? = nil
    /// Last server evaluation: "ok" | "worse" | "bad".
    var serverState: String? = nil
    var serverScore: Int? = nil
    var serverCapReason: String? = nil
    /// The server's suggestion when worse / bad ("time" | "spot" | "none").
    var altType: String? = nil
    var altStart: Date? = nil
    var altEnd: Date? = nil
    var altSpotID: UUID? = nil
    var altSpotName: String? = nil
    var altSpotKind: String? = nil
    var altScore: Int? = nil
    /// Set when a plan push for this plan was opened; an alternative applied
    /// afterwards counts as `plan_changed_after_alert`.
    var alertOpenedAt: Date? = nil

    init(window: PlanWindow) {
        planID = UUID()
        spotID = window.spotID
        spotName = window.spotName
        tz = window.timeZone.identifier
        start = window.start
        end = window.end
        scoreAtSave = window.score
        createdAt = .now
    }

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    var window: PlanWindow {
        PlanWindow(spotID: spotID, spotName: spotName, timeZone: timeZone,
                   start: start, end: end, score: scoreAtSave)
    }

    func isEnded(now: Date = .now) -> Bool { end <= now }

    var snapshot: PlanSnapshot {
        PlanSnapshot(spotID: spotID, spotName: spotName, tz: tz, start: start, end: end,
                     scoreAtSave: scoreAtSave, serverStatus: serverStatus)
    }

    var isSynced: Bool { serverID != nil }

    /// The server's status while synced and evaluated; callers fall back to
    /// the local forecast check otherwise (never both at once).
    var serverStatus: PlanStatus? {
        isSynced ? PlanStatus(serverState: serverState) : nil
    }

    var alternative: PlanAlternative? {
        guard isSynced, let altType else { return nil }
        return PlanAlternative(type: altType, start: altStart, end: altEnd, spotId: altSpotID,
                               spotName: altSpotName, spotKind: altSpotKind, score: altScore)
    }

    /// Copies the server's view of this plan (owner role).
    func apply(_ remote: ServerPlan) {
        serverID = remote.id
        shareToken = remote.shareToken
        serverState = remote.state
        serverScore = remote.score
        serverCapReason = remote.capReason
        let alt = remote.alternative
        altType = alt?.type
        altStart = alt?.start
        altEnd = alt?.end
        altSpotID = alt?.spotId
        altSpotName = alt?.spotName
        altSpotKind = alt?.spotKind
        altScore = alt?.score
    }

    /// Forecast alerts off: the plan is local-only again.
    func clearSync() {
        serverID = nil
        shareToken = nil
        serverState = nil
        serverScore = nil
        serverCapReason = nil
        altType = nil
        altStart = nil
        altEnd = nil
        altSpotID = nil
        altSpotName = nil
        altSpotKind = nil
        altScore = nil
        alertOpenedAt = nil
    }
}

enum PicnicPlans {
    /// Where a plan was made — the only analytics prop (no spot, no time).
    enum Source: String {
        case decision, week, chart
    }

    /// Adds a plan unless the same spot already has one starting at the
    /// same hour. Returns false for a duplicate.
    @MainActor
    @discardableResult
    static func add(_ window: PlanWindow, existing: [PicnicPlan], context: ModelContext) -> Bool {
        guard !contains(window, in: existing) else { return false }
        context.insert(PicnicPlan(window: window))
        return true
    }

    /// Plans shown in Saved: upcoming, and ended ones until their day is
    /// over (marked "Ended"). Older ones are hidden, then pruned.
    static func visible(_ plans: [PicnicPlan], now: Date = .now, calendar: Calendar = .current) -> [PicnicPlan] {
        let today = calendar.startOfDay(for: now)
        return plans.filter { $0.end > today }
    }

    static func contains(_ window: PlanWindow, in existing: [PicnicPlan]) -> Bool {
        existing.contains { $0.spotID == window.spotID && abs($0.start.timeIntervalSince(window.start)) < 60 }
    }

    /// The link a plan shares and puts in Calendar: the share page at the
    /// plan's hour, else the app link.
    static func link(for window: PlanWindow) -> URL {
        SpotLink.shareURL(spotID: window.spotID, at: window.start)
            ?? SpotLink.appURL(spotID: window.spotID, at: window.start)
    }

    /// A synced plan shares its plan page (`/p/<token>`, followable);
    /// a local one the timed spot link.
    @MainActor
    static func link(for plan: PicnicPlan) -> URL {
        if let token = plan.shareToken, let url = PlanShareLink.url(token: token) { return url }
        return link(for: plan.window)
    }
}

/// Current status of each upcoming plan, from one forecast call per
/// distinct spot (the same call Spot Detail and This Week use).
@MainActor @Observable
final class PlanStatusModel {
    private(set) var statuses: [UUID: PlanStatus] = [:]

    /// Ended plans are skipped (no forecast for past hours).
    func load(plans: [PicnicPlan], now: Date = .now) async {
        let upcoming = plans.filter { !$0.isEnded(now: now) }
        let inputs = upcoming.map { (planID: $0.planID, spotID: $0.spotID, start: $0.start, end: $0.end,
                                     scoreAtSave: $0.scoreAtSave) }
        let spotIDs = Array(Set(inputs.map(\.spotID)))
        guard !spotIDs.isEmpty else { statuses = [:]; return }

        var hoursBySpot: [UUID: [ScoredHour]] = [:]
        await withTaskGroup(of: (UUID, [ScoredHour]?).self) { group in
            for id in spotIDs {
                group.addTask {
                    let points = try? await AppConfig.apiClient.forecast(spotID: id)
                    return (id, points?.map { ScoredHour(tsHour: $0.tsHour, score: $0.score, capReason: $0.capReason) })
                }
            }
            for await (id, hours) in group {
                if let hours { hoursBySpot[id] = hours }
            }
        }
        if Task.isCancelled { return }
        var result: [UUID: PlanStatus] = [:]
        for input in inputs {
            guard let hours = hoursBySpot[input.spotID],
                  let status = PlanStatus.classify(hours: hours, start: input.start, end: input.end,
                                                   scoreAtSave: input.scoreAtSave) else { continue }
            result[input.planID] = status
        }
        statuses = result
    }
}
