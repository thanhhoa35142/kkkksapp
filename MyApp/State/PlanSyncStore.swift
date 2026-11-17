import Foundation
import Observation
import SwiftData


@MainActor @Observable
final class PlanSyncStore {
    enum Result: Equatable {
        case done
        case needsPlus
        /// Notifications are off for the app: nothing could reach the user.
        case denied
        /// Follow of a token this device owns.
        case ownPlan
        case failed(String)
    }

    /// Active plans with forecast alerts (backend `plans.Limits`; the server
    /// enforces them — these are for display).
    nonisolated static let freeLimit = 1
    nonisolated static let plusLimit = 20

    /// Active followed plans, by start.
    private(set) var followed: [ServerPlan] = []
    /// Local plan ids with a request in flight (toggle shows progress).
    private(set) var busy: Set<UUID> = []
    /// Bumped to ask the root to reconcile (it has the model context).
    private(set) var syncRequest = 0

    /// Creates in flight: a sync must not take their new server plan for
    /// one to import before the local plan has its `serverID`.
    private var creating = 0
    private var api: APIClient { AppConfig.apiClient }
    private let defaults: UserDefaults
    private static let pendingKey = "planSync.pendingCancels"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Server ids of plans deleted on this device whose cancel hasn't been
    /// confirmed yet. Ids only — no place or time.
    private(set) var pendingCancels: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Self.pendingKey) ?? []).compactMap(UUID.init(uuidString:))) }
        set { defaults.set(newValue.map(\.uuidString).sorted(), forKey: Self.pendingKey) }
    }

    func requestSync() { syncRequest += 1 }

    func isFollowing(token: String) -> Bool {
        followed.contains { $0.shareToken == token }
    }

    // MARK: Sync

    /// Fetches the list and reconciles it with the local plans
    /// (`PlanReconcile`): refresh, attach, re-import, retry pending cancels.
    func sync(local: [PicnicPlan], context: ModelContext, now: Date = .now) async {
        guard creating == 0 else { return }
        let items: [ServerPlan]
        do {
            items = try await api.plans()
        } catch {
            Log.api.error("plans load failed: \(error.localizedDescription)")
            return
        }
        guard creating == 0 else { return }
        followed = items.filter { $0.isFollower && $0.isActive }.sorted { $0.start < $1.start }

        // Re-read after the await: an overlapping sync (launch + foreground)
        // may have imported plans since `local` was taken. The fetch sees
        // unsaved inserts, and from here to the inserts nothing awaits.
        let current = (try? context.fetch(FetchDescriptor<PicnicPlan>())) ?? local
        let alive = current.filter { !$0.isDeleted && $0.modelContext != nil }
        let outcome = PlanReconcile.decide(
            local: alive.map { PlanReconcile.Local(planID: $0.planID, serverID: $0.serverID,
                                                   spotID: $0.spotID, start: $0.start, end: $0.end) },
            owned: items.filter(\.isOwner), pendingCancels: pendingCancels, now: now)
        for plan in alive {
            if let remote = outcome.apply[plan.planID] {
                plan.apply(remote)
            } else if outcome.unsync.contains(plan.planID) {
                plan.clearSync()
            }
        }
        for remote in outcome.importPlans {
            var window = remote.window
            // The plan's own baseline, not the live score, is "when you planned it".
            if let baseline = remote.baselineScore {
                window = PlanWindow(spotID: window.spotID, spotName: window.spotName, timeZone: window.timeZone,
                                    start: window.start, end: window.end, score: baseline)
            }
            let plan = PicnicPlan(window: window)
            context.insert(plan)
            plan.apply(remote)
        }
        if !outcome.clearPending.isEmpty {
            pendingCancels.subtract(outcome.clearPending)
        }
        for id in outcome.cancel {
            await cancelPending(id)
        }
    }

    // MARK: Owned plans

    /// Turns forecast alerts on: asks for notification permission (the
    /// contextual moment), registers for APNs, then creates the server plan.
    /// On any failure the local plan stays as it was.
    func enable(_ plan: PicnicPlan, now: Date = .now) async -> Result {
        guard case let .ok(start, end) = PlanSyncRules.window(start: plan.start, end: plan.end, now: now) else {
            return .failed(PlanErrorMessage.window(PlanSyncRules.window(start: plan.start, end: plan.end, now: now))
                           ?? PlanErrorMessage.text(code: nil, context: .create))
        }
        guard await Self.allowNotifications() else { return .denied }
        let localID = plan.planID
        busy.insert(localID)
        creating += 1
        defer {
            busy.remove(localID)
            creating -= 1
        }
        do {
            let remote = try await api.createPlan(PlanCreateRequest(
                spotId: plan.spotID, start: start, end: end, tz: plan.tz))
            guard !plan.isDeleted, plan.modelContext != nil else {
                // Deleted while the request was out: don't leave it on the server.
                pendingCancels.insert(remote.id)
                await cancelPending(remote.id)
                return .failed(PlanErrorMessage.text(code: nil, context: .create))
            }
            plan.apply(remote)
            return .done
        } catch let error as APIError where error.code == "plan_limit" {
            return .needsPlus
        } catch {
            Log.api.error("plan create failed: \(error.localizedDescription)")
            return .failed(PlanErrorMessage.text(for: error, context: .create))
        }
    }

    /// Turns forecast alerts off. 404 counts as done (already gone).
    func disable(_ plan: PicnicPlan) async -> Result {
        guard let id = plan.serverID else { return .done }
        let localID = plan.planID
        busy.insert(localID)
        defer { busy.remove(localID) }
        do {
            try await api.cancelPlan(id: id)
        } catch let error as APIError where error.code == "not_found" {
            // Not on the server any more: nothing to cancel.
        } catch {
            Log.api.error("plan cancel failed: \(error.localizedDescription)")
            return .failed(PlanErrorMessage.text(for: error, context: .cancel))
        }
        if !plan.isDeleted { plan.clearSync() }
        return .done
    }

    /// A synced plan is being deleted locally: cancel it on the server in the
    /// background. Recorded first, so a failed cancel is retried next sync
    /// and the plan isn't re-imported meanwhile.
    func forget(serverID: UUID?) {
        guard let serverID else { return }
        pendingCancels.insert(serverID)
        Task { await cancelPending(serverID) }
    }

    /// Cancels a pending server plan; done (and dropped) on success or 404.
    private func cancelPending(_ id: UUID) async {
        do {
            try await api.cancelPlan(id: id)
        } catch let error as APIError where error.code == "not_found" {
            // Already gone.
        } catch {
            Log.api.error("plan cancel failed, retried next sync: \(error.localizedDescription)")
            return
        }
        pendingCancels.remove(id)
    }

    // MARK: Followed plans

    func follow(token: String) async -> Result {
        guard PlanShareLink.isValidToken(token) else {
            return .failed(PlanErrorMessage.text(code: "not_found", context: .follow))
        }
        guard await Self.allowNotifications() else { return .denied }
        do {
            let plan = try await api.followPlan(token: token)
            followed.removeAll { $0.shareToken == token }
            followed.append(plan)
            followed.sort { $0.start < $1.start }
            return .done
        } catch let error as APIError where error.code == "own_plan" {
            return .ownPlan
        } catch {
            Log.api.error("plan follow failed: \(error.localizedDescription)")
            return .failed(PlanErrorMessage.text(for: error, context: .follow))
        }
    }

    /// Always 204 on the server; a failed call is restored by the next sync.
    func unfollow(token: String) async {
        followed.removeAll { $0.shareToken == token }
        do { try await api.unfollowPlan(token: token) } catch {
            Log.api.error("plan unfollow failed: \(error.localizedDescription)")
        }
    }

    /// Delete My Data: the device row (and with it every server plan and
    /// follow) is deleted by `AppState.deleteMyData`.
    func reset() {
        followed = []
        busy = []
        pendingCancels = []
    }

    // MARK: Permission

    /// Same flow as alerts (`AlertsStore.save`): prompt in context, then
    /// register for APNs so the token reaches the server.
    static func allowNotifications() async -> Bool {
        let granted = await PushManager.shared.requestAuthorization()
        if granted { await PushManager.shared.registerIfAuthorized() }
        return granted
    }
}
