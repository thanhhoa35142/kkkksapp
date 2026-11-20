import Foundation

// Pure rules for server-synced plans (C2) — unit-tested in PlanSyncTests.

enum PlanSyncRules {
    /// Server bounds (backend plans.go): 1–12 h, start after now (to the
    /// minute), end within the 7-day scoring horizon.
    static let minWindow: TimeInterval = 3600
    static let maxWindow: TimeInterval = 12 * 3600
    static let horizonDays = 7
    /// Seconds the start must lead "now" by, so a slow request still lands
    /// after the server's clock (it truncates the start to the minute).
    static let startLead: TimeInterval = 120

    enum Window: Equatable {
        /// The window to send (the start moved up to just after now when the
        /// plan has begun; the local plan keeps its own times).
        case ok(start: Date, end: Date)
        /// Under an hour left (or ended): alerts are no use any more.
        case tooLate
        /// Ends past the forecast; alerts can be turned on closer to the day.
        case tooFar
        /// Shorter than 1 h or longer than 12 h.
        case invalidLength

        var isOK: Bool {
            if case .ok = self { return true }
            return false
        }
    }

    static func window(start: Date, end: Date, now: Date = .now) -> Window {
        guard end.timeIntervalSince(start) >= minWindow, end.timeIntervalSince(start) <= maxWindow else {
            return .invalidLength
        }
        let minute = (now.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60
        let earliest = Date(timeIntervalSinceReferenceDate: minute + startLead)
        let from = max(start, earliest)
        guard end.timeIntervalSince(from) >= minWindow else { return .tooLate }
        let hour = (now.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
        let horizon = Date(timeIntervalSinceReferenceDate: hour + TimeInterval(horizonDays) * 86_400)
        guard end <= horizon else { return .tooFar }
        return .ok(start: from, end: end)
    }

    /// The plan an alternative turns into: same spot at the suggested time
    /// ("time"), or the suggested spot at the planned time ("spot"). nil for
    /// "none", unknown types and incomplete data.
    static func window(applying alternative: PlanAlternative, to plan: PlanWindow) -> PlanWindow? {
        switch alternative.type {
        case "time":
            guard let start = alternative.start, let end = alternative.end, end > start else { return nil }
            return PlanWindow(spotID: plan.spotID, spotName: plan.spotName, timeZone: plan.timeZone,
                              start: start, end: end, score: alternative.score ?? 0)
        case "spot":
            guard let spotID = alternative.spotId, spotID != plan.spotID else { return nil }
            let name = alternative.spotName?.trimmingCharacters(in: .whitespaces) ?? ""
            return PlanWindow(spotID: spotID,
                              spotName: name.isEmpty ? KindStyle.label(alternative.spotKind ?? "") : name,
                              timeZone: plan.timeZone, start: plan.start, end: plan.end,
                              score: alternative.score ?? 0)
        default:
            return nil
        }
    }
}


enum PlanReconcile {
    struct Local: Equatable {
        let planID: UUID
        let serverID: UUID?
        let spotID: UUID
        let start: Date
        let end: Date
    }

    struct Outcome: Equatable {
        /// Local plan id → its server plan (refresh, or attach).
        var apply: [UUID: ServerPlan] = [:]
        /// Local plan ids to make local-only again.
        var unsync: [UUID] = []
        var importPlans: [ServerPlan] = []
        /// Server ids to cancel (pending cancels still active).
        var cancel: [UUID] = []
        /// Pending cancels that are done (server plan gone, canceled or ended).
        var clearPending: Set<UUID> = []
    }

    static func decide(local: [Local], owned: [ServerPlan], pendingCancels: Set<UUID>,
                       now: Date = .now) -> Outcome {
        var outcome = Outcome()
        let byID = Dictionary(owned.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for plan in local {
            guard let id = plan.serverID else { continue }
            if let remote = byID[id], remote.status != "canceled" {
                outcome.apply[plan.planID] = remote
            } else if plan.end > now {
                outcome.unsync.append(plan.planID)
            }
        }
        let active = owned.filter(\.isActive).sorted { $0.start < $1.start }
        let activeIDs = Set(active.map(\.id))
        outcome.cancel = active.map(\.id).filter { pendingCancels.contains($0) }
        outcome.clearPending = pendingCancels.subtracting(activeIDs)

        let linked = Set(local.compactMap(\.serverID))
        var unsynced = local.filter { $0.serverID == nil }
        for remote in active where !linked.contains(remote.id) && !pendingCancels.contains(remote.id) {
            // The server start may have been moved up to "now" on create.
            if let index = unsynced.firstIndex(where: {
                $0.spotID == remote.spot.id && $0.end == remote.end && $0.start <= remote.start
            }) {
                outcome.apply[unsynced[index].planID] = remote
                unsynced.remove(at: index)
            } else {
                outcome.importPlans.append(remote)
            }
        }
        return outcome
    }
}

/// Plan links: `https://<share host>/p/<token>` and `pickhour://plan/<token>`.
/// Tokens are checked for shape before any network call.
enum PlanShareLink {
    /// 128 random bits, base64url without padding (backend `ValidToken`).
    static func isValidToken(_ token: String) -> Bool {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return token.unicodeScalars.count == 22 && token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    static func url(token: String, base: URL? = AppConfig.shareBaseURL) -> URL? {
        guard isValidToken(token) else { return nil }
        return base?.appendingPathComponent("p").appendingPathComponent(token)
    }

    static func appURL(token: String) -> URL? {
        guard isValidToken(token) else { return nil }
        return URL(string: "pickhour://plan/\(token)")
    }

    static func token(from url: URL, shareBase: URL? = AppConfig.shareBaseURL) -> String? {
        var candidate: String?
        if url.scheme == "pickhour", url.host == "plan" {
            let parts = url.pathComponents  // ["/", "<token>"]
            if parts.count == 2 { candidate = parts[1] }
        } else if let shareHost = shareBase?.host, url.scheme == "https",
                  url.host?.lowercased() == shareHost.lowercased() {
            let parts = url.pathComponents  // ["/", "p", "<token>"]
            if parts.count == 3, parts[1] == "p" { candidate = parts[2] }
        }
        guard let candidate, isValidToken(candidate) else { return nil }
        return candidate
    }
}

/// Server reason codes → a sentence for the plan screens. The server sends
/// codes only (CLAUDE.md); the app owns the wording.
enum PlanErrorMessage {
    enum Context { case create, cancel, follow, shared }

    static func text(for error: Error, context: Context) -> String {
        text(code: (error as? APIError)?.code, context: context)
    }

    static func text(code: String?, context: Context) -> String {
        switch code {
        case "plan_start_past":
            return String(localized: "This plan has already started, so there's nothing left to alert you about.")
        case "plan_window_invalid":
            return String(localized: "Forecast alerts work for plans from 1 to 12 hours long.")
        case "plan_beyond_horizon":
            return String(localized: "This plan is past the 7-day forecast. Turn alerts on closer to the day.")
        case "invalid_tz":
            return String(localized: "This plan can't be opened here.")
        case "not_found":
            return context == .create
                ? String(localized: "This spot is no longer available.")
                : String(localized: "This plan is no longer available.")
        case "follower_limit":
            return String(localized: "This plan already has as many followers as it can.")
        case "follow_limit":
            return String(localized: "You're following as many plans as you can. Unfollow one first.")
        case "own_plan":
            return String(localized: "This is your own plan.")
        case "plan_limit":
            return String(localized: "You've reached your limit of plans with forecast alerts.")
        case "rate_limited":
            return String(localized: "That was quick. Try again in a moment.")
        default:
            switch context {
            case .create: return String(localized: "Couldn't turn on forecast alerts. Try again later.")
            case .cancel: return String(localized: "Couldn't turn off forecast alerts. Try again later.")
            case .follow: return String(localized: "Couldn't follow this plan. Try again later.")
            case .shared: return String(localized: "Couldn't load this plan. Try again later.")
            }
        }
    }

    static func window(_ result: PlanSyncRules.Window) -> String? {
        switch result {
        case .ok: nil
        case .tooLate: text(code: "plan_start_past", context: .create)
        case .tooFar: text(code: "plan_beyond_horizon", context: .create)
        case .invalidLength: text(code: "plan_window_invalid", context: .create)
        }
    }
}
