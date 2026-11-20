import SwiftData
import SwiftUI

/// Server-synced plans at the root (C2): reconciles with the server when
/// asked (launch, foreground), opens plan pushes, and hosts the plan sheet.
/// Applied once in `RootView`, so it runs whichever tab is open.
struct PlanRouting: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [PicnicPlan]
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .task(id: app.planSync.syncRequest) {
                guard app.planSync.syncRequest > 0 else { return }
                await app.planSync.sync(local: plans, context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    Task { await app.flushEventsForBackground() }
                    return
                }
                guard phase == .active else { return }
                app.planSync.requestSync()
                Task {
                    await app.checkAppVersion()
                    await app.touchDeviceIfStale()
                }
            }
            // `.task` covers a tap that launched the app (set before this
            // view existed, so `onChange` never sees it).
            .task { openPendingPlan() }
            .onChange(of: DeepLinkRouter.shared.pendingPlan) { _, newValue in
                if newValue != nil { openPendingPlan() }
            }
            .sheet(item: $app.planSheet, onDismiss: showDeferredPaywall) { sheet in
                PlanSheetContent(sheet: sheet)
            }
    }

    /// Owner: the local plan with that server id. Follower (or a plan this
    /// install no longer has): the shared view by token.
    private func openPendingPlan() {
        guard let target = DeepLinkRouter.shared.consumePlan() else { return }
        let own = plans.first { plan in
            guard !plan.isDeleted else { return false }
            if let id = target.planID, plan.serverID == id { return true }
            if let token = target.shareToken, plan.shareToken == token { return true }
            return false
        }
        if let own {
            own.alertOpenedAt = .now
            app.track("plan_alert_opened", ["role": .string("owner"), "kind": .string(target.kind)])
            app.planSheet = .own(planID: own.planID)
        } else if let token = target.shareToken {
            app.track("plan_alert_opened", ["role": .string("follower"), "kind": .string(target.kind)])
            app.planSheet = .shared(token: token)
        }
    }

    /// A paywall asked for inside the plan sheet opens after it closes.
    private func showDeferredPaywall() {
        guard let reason = app.deferredPaywall else { return }
        app.deferredPaywall = nil
        app.paywall = reason
    }
}

/// The plan sheet's root: a shared token that is one of the user's own
/// plans opens that plan instead.
private struct PlanSheetContent: View {
    let sheet: PlanSheet
    @Query private var plans: [PicnicPlan]

    var body: some View {
        NavigationStack {
            switch sheet {
            case .own(let planID):
                PlanDetailView(planID: planID)
            case .shared(let token):
                if let own = plans.first(where: { $0.shareToken == token }) {
                    PlanDetailView(planID: own.planID)
                } else {
                    SharedPlanView(token: token)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 560)
        #endif
    }
}
