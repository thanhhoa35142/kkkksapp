import SwiftData
import SwiftUI

/// One of the user's plans (plan sheet): how it looks now, the server's
/// suggestion when it turned worse, and the per-plan opt-in to forecast
/// alerts (C2) — the moment notification permission is asked for.
/// One status at a time: the server's when synced, else the local check.
struct PlanDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var plans: [PicnicPlan]
    /// Changes when an alternative replaces the plan.
    @State private var planID: UUID
    @State private var localStatus = PlanStatusModel()
    /// The toggle's value while a request is out (reverts on failure).
    @State private var pendingAlerts: Bool?
    @State private var message: String?
    @State private var notificationsDenied = false
    @State private var applying = false

    init(planID: UUID) {
        _planID = State(initialValue: planID)
    }

    private var plan: PicnicPlan? {
        plans.first { $0.planID == planID && !$0.isDeleted }
    }

    var body: some View {
        Group {
            if let plan {
                form(plan)
            } else {
                ContentUnavailableView("Plan Deleted", systemImage: "calendar.badge.minus",
                                       description: Text("This plan is no longer on this device."))
            }
        }
        .navigationTitle("Plan")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func form(_ plan: PicnicPlan) -> some View {
        let window = plan.window
        let ended = plan.isEnded()
        let status = plan.serverStatus ?? localStatus.statuses[plan.planID]
        return Form {
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(PlanWindowRow.dayLabel(window)) · \(PlanWindowRow.rangeLabel(window))")
                            .font(.headline)
                            .monospacedDigit()
                        Text(plan.spotName)
                            .foregroundStyle(.secondary)
                        PlanStatusLabel(status: status, ended: ended, capReason: plan.serverCapReason)
                    }
                    Spacer(minLength: 8)
                    if !ended {
                        ScoreBadge(score: plan.serverScore ?? plan.scoreAtSave, diameter: 44)
                    }
                }
                .accessibilityElement(children: .combine)
            } footer: {
                if !ended, plan.serverScore != nil, plan.serverScore != plan.scoreAtSave {
                    Text("Scored \(plan.scoreAtSave) when you planned it.")
                }
            }

            if !ended, let alternative = plan.alternative,
               let better = PlanSyncRules.window(applying: alternative, to: window) {
                suggestionSection(plan, alternative: alternative, better: better)
            }

            if !ended {
                alertsSection(plan)
            }

            Section {
                Button("Open Spot", systemImage: "map") {
                    dismiss()
                    app.selectedTab = .map
                    app.open(spotID: plan.spotID, at: plan.start, focusMap: true)
                }
                ShareLink(item: PicnicPlans.link(for: plan), subject: Text(window.spotName),
                          message: Text(window.shareText)) {
                    Label("Share Plan", systemImage: "square.and.arrow.up")
                }
                Button("Delete Plan", systemImage: "trash", role: .destructive) {
                    app.planSync.forget(serverID: plan.serverID)
                    context.delete(plan)
                    dismiss()
                }
            } footer: {
                if plan.isSynced {
                    Text("People with the link can see the spot, time and forecast, and follow the plan. They don't see who you are.")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: plan.planID) {
            // The local check only when the server has no status for it.
            if plan.serverStatus == nil, !ended {
                await localStatus.load(plans: [plan])
            }
        }
    }

    // MARK: Suggestion

    private func suggestionSection(_ plan: PicnicPlan, alternative: PlanAlternative,
                                   better: PlanWindow) -> some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if alternative.type == "time" {
                        Text(verbatim: PlanWindowRow.rangeLabel(better))
                            .font(.headline)
                            .monospacedDigit()
                        Text("Same spot, better hours")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(better.spotName)
                            .font(.headline)
                        Text("Nearby, at the same time")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let score = alternative.score {
                    ScoreBadge(score: score, diameter: 36)
                }
            }
            .accessibilityElement(children: .combine)
            Button {
                Task { await apply(better, alternative: alternative, replacing: plan) }
            } label: {
                Label("Change Plan to This", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(applying)
        } header: {
            Text("Looks Better")
        }
    }

    // MARK: Forecast alerts

    private func alertsSection(_ plan: PicnicPlan) -> some View {
        let eligibility = PlanSyncRules.window(start: plan.start, end: plan.end)
        let busy = app.planSync.busy.contains(plan.planID)
        return Section {
            Toggle(isOn: Binding(
                get: { pendingAlerts ?? plan.isSynced },
                set: { newValue in Task { await setAlerts(newValue, for: plan) } }
            )) {
                HStack {
                    Text("Tell me if the forecast changes")
                    if busy {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(busy || (!plan.isSynced && !eligibility.isOK))
            if notificationsDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off for Pickhour. Turn them on in Settings to get forecast alerts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { openNotificationSettings() }
                        .font(.footnote)
                }
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !plan.isSynced, let reason = PlanErrorMessage.window(eligibility) {
                Text(reason)
            } else {
                Text("We'll notify you if the forecast for this time gets worse, and the evening before if it still looks good. This keeps the spot and time on Pickhour's server until a month after the plan.")
            }
        }
    }

    private func setAlerts(_ on: Bool, for plan: PicnicPlan) async {
        guard pendingAlerts == nil else { return }
        pendingAlerts = on
        message = nil
        defer { pendingAlerts = nil }
        let result: PlanSyncStore.Result
        if on {
            result = await app.planSync.enable(plan)
        } else {
            result = await app.planSync.disable(plan)
        }
        handle(result, enabling: on)
    }

    private func handle(_ result: PlanSyncStore.Result, enabling: Bool) {
        switch result {
        case .done:
            notificationsDenied = false
            if enabling { app.track("plan_sync_enabled") }
        case .needsPlus:
            message = PlanErrorMessage.text(code: "plan_limit", context: .create)
            app.deferredPaywall = .plans
            dismiss()
        case .denied:
            notificationsDenied = true
        case .ownPlan:
            break
        case .failed(let text):
            message = text
        }
    }

    // MARK: Apply a suggestion

    /// Replaces the plan with the suggestion. A synced plan is canceled on
    /// the server first (Free has one active plan), then the new one synced.
    private func apply(_ better: PlanWindow, alternative: PlanAlternative, replacing plan: PicnicPlan) async {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        message = nil
        let wasSynced = plan.isSynced
        let afterAlert = plan.alertOpenedAt != nil
        if wasSynced, case .failed(let text) = await app.planSync.disable(plan) {
            message = text
            return
        }
        let replacement: PicnicPlan
        if let existing = plans.first(where: { !$0.isDeleted && $0.planID != plan.planID
                                                && PicnicPlans.contains(better, in: [$0]) }) {
            replacement = existing
        } else {
            replacement = PicnicPlan(window: better)
            context.insert(replacement)
        }
        context.delete(plan)
        planID = replacement.planID
        app.track(afterAlert ? "plan_changed_after_alert" : "plan_alternative_applied",
                  ["type": .string(alternative.type)])
        if wasSynced, !replacement.isSynced {
            handle(await app.planSync.enable(replacement), enabling: true)
        }
    }

    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            openURL(url)
        }
        #endif
    }
}
