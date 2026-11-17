import SwiftUI

/// A plan someone shared (`/p/<token>`, a follower push, a followed row):
/// the anonymous token view — spot, window, forecast — and Follow to get the
/// same forecast alerts. Unknown, canceled and ended plans read as one
/// neutral "no longer available".
struct SharedPlanView: View {
    let token: String

    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: Phase = .loading
    @State private var working = false
    @State private var message: String?
    @State private var notificationsDenied = false

    private enum Phase {
        case loading
        case loaded(SharedPlan)
        case unavailable
        case failed(String)
    }

    var body: some View {
        content
            .navigationTitle("Shared Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: token) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            ContentUnavailableView {
                Label("Plan No Longer Available", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("This plan has ended or was removed.")
            } actions: {
                if app.planSync.isFollowing(token: token) {
                    Button("Remove from Plans") {
                        Task {
                            await app.planSync.unfollow(token: token)
                            dismiss()
                        }
                    }
                }
            }
        case .failed(let text):
            ContentUnavailableView {
                Label("Couldn't Load Plan", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loaded(let plan):
            form(plan)
        }
    }

    private func form(_ plan: SharedPlan) -> some View {
        let window = plan.window
        let following = app.planSync.isFollowing(token: token)
        let reasons = (plan.reasons ?? []).filter { ReasonLocalizer.isKnown($0.code) }
        return Form {
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(PlanWindowRow.dayLabel(window)) · \(PlanWindowRow.rangeLabel(window))")
                            .font(.headline)
                            .monospacedDigit()
                        Text(window.spotName)
                            .foregroundStyle(.secondary)
                        PlanStatusLabel(status: plan.planStatus, capReason: plan.capReason)
                    }
                    Spacer(minLength: 8)
                    if let score = plan.score {
                        ScoreBadge(score: score, capReason: plan.capReason, diameter: 44)
                    }
                }
                .accessibilityElement(children: .combine)
                ForEach(reasons.indices, id: \.self) { index in
                    let reason = reasons[index]
                    Label(ReasonLocalizer.text(for: reason),
                          systemImage: ReasonLocalizer.symbol(for: reason.code) ?? "info.circle")
                        .font(.subheadline)
                }
            } footer: {
                Text("Times are local to the spot.")
            }

            Section {
                if following {
                    Label("You're following this plan", systemImage: "bell")
                    Button("Unfollow", role: .destructive) {
                        Task { await app.planSync.unfollow(token: token) }
                    }
                } else {
                    Button {
                        Task { await follow() }
                    } label: {
                        HStack {
                            Label("Follow Plan", systemImage: "bell.badge")
                            if working {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(working)
                }
                if notificationsDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications are off for Pickhour. Turn them on in Settings to follow plans.")
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
                if !following {
                    Text("Get the same forecast alerts as the person who shared it. They won't see who you are.")
                }
            }

            Section {
                Button("Open Spot", systemImage: "map") {
                    dismiss()
                    app.selectedTab = .map
                    app.open(spotID: plan.spot.id, at: plan.start, focusMap: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func load() async {
        // Shape check before any request (also done when parsing links).
        guard PlanShareLink.isValidToken(token) else { phase = .unavailable; return }
        if case .loaded = phase {} else { phase = .loading }
        do {
            phase = .loaded(try await AppConfig.apiClient.sharedPlan(token: token))
        } catch let error as APIError where error.code == "not_found" {
            phase = .unavailable
        } catch {
            if case .loaded = phase { return }  // keep what's shown
            phase = .failed(PlanErrorMessage.text(for: error, context: .shared))
        }
    }

    private func follow() async {
        guard !working else { return }
        working = true
        defer { working = false }
        message = nil
        switch await app.planSync.follow(token: token) {
        case .done:
            notificationsDenied = false
            app.track("plan_followed")
        case .denied:
            notificationsDenied = true
        case .ownPlan:
            // Not on this device any more (reinstall): nothing to follow.
            message = PlanErrorMessage.text(code: "own_plan", context: .follow)
        case .needsPlus:
            break
        case .failed(let text):
            message = text
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
