/// Saved › Plans — picnics the user planned (stored on device), then plans
/// shared with the user that they follow (C2, from the server). Each row
/// shows how the window looks now; tapping one opens the plan sheet.
/// Free and Plus. Hidden when empty. Used in the Saved tab and the iPad/Mac
/// sidebar. The screen holding it applies
/// `.picnicPlanSupport(status:calendarWindow:)` once (status loading + the
/// Calendar sheet on a stable view, not per row).
struct PlansSection: View {
    let status: PlanStatusModel
    @Binding var calendarWindow: PlanWindow?
    /// Kept for the call sites; both styles open the plan sheet (a sheet
    /// works the same in the tab's stack and the sidebar).
    var rowStyle: BestNowRows.RowStyle = .push

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \PicnicPlan.start) private var plans: [PicnicPlan]

    var body: some View {
        let visible = PicnicPlans.visible(plans)
        let followed = app.planSync.followed
        if !visible.isEmpty || !followed.isEmpty {
            Section {
                ForEach(visible) { plan in
                    row(plan)
                }
                .onDelete { offsets in
                    for index in offsets where visible.indices.contains(index) {
                        delete(visible[index])
                    }
                }
                ForEach(followed) { plan in
                    followedRow(plan)
                }
            } header: {
                Text("Plans")
            } footer: {
                if visible.contains(where: \.isSynced) || !followed.isEmpty {
                    Text("Plans with forecast alerts are also kept on Pickhour's server until a month after they end. Others stay on this device.")
                } else {
                    Text("Plans stay on this device.")
                }
            }
        }
    }

    private func row(_ plan: PicnicPlan) -> some View {
        Button {
            app.planSheet = .own(planID: plan.planID)
        } label: {
            PicnicPlanRow(plan: plan, status: plan.serverStatus ?? status.statuses[plan.planID])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { actions(plan) }
    }

    private func followedRow(_ plan: ServerPlan) -> some View {
        Button {
            app.planSheet = .shared(token: plan.shareToken)
        } label: {
            FollowedPlanRow(plan: plan)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Unfollow", systemImage: "bell.slash", role: .destructive) {
                Task { await app.planSync.unfollow(token: plan.shareToken) }
            }
        }
        .swipeActions {
            Button("Unfollow", role: .destructive) {
                Task { await app.planSync.unfollow(token: plan.shareToken) }
            }
        }
    }

    @ViewBuilder
    private func actions(_ plan: PicnicPlan) -> some View {
        let window = plan.window
        ShareLink(item: PicnicPlans.link(for: plan), subject: Text(window.spotName),
                  message: Text(window.shareText)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        #if os(iOS)
        Button("Add to Calendar", systemImage: "calendar.badge.plus") {
            calendarWindow = window
            app.track("plan_calendar", ["source": .string("plans")])
        }
        #endif
        Button("Delete", systemImage: "trash", role: .destructive) {
            delete(plan)
        }
    }

    /// A synced plan is canceled on the server too (in the background).
    private func delete(_ plan: PicnicPlan) {
        app.planSync.forget(serverID: plan.serverID)
        context.delete(plan)
    }
}

/// Loads plan statuses, prunes old plans and hosts the Calendar sheet for
/// `PlansSection` — applied once to the list that contains it.
private struct PicnicPlanSupport: ViewModifier {
    let status: PlanStatusModel
    @Binding var calendarWindow: PlanWindow?

    @Environment(\.modelContext) private var context
    @Query(sort: \PicnicPlan.start) private var plans: [PicnicPlan]

    func body(content: Content) -> some View {
        content
            .task(id: PicnicPlans.visible(plans).map(\.planID)) {
                pruneEnded()
                await status.load(plans: PicnicPlans.visible(plans))
            }
            #if os(iOS)
            .sheet(item: $calendarWindow) { window in
                CalendarEventSheet(
                    title: String(localized: "Picnic at \(window.spotName)"),
                    start: window.start, end: window.end, timeZone: window.timeZone,
                    url: PicnicPlans.link(for: window)) { calendarWindow = nil }
                    .ignoresSafeArea()
            }
            #endif
    }

    /// Plans that ended more than a week ago are of no use: delete them.
    private func pruneEnded() {
        let cutoff = Date.now.addingTimeInterval(-7 * 86_400)
        for plan in plans where plan.end < cutoff {
            context.delete(plan)
        }
    }
}

extension View {
    func picnicPlanSupport(status: PlanStatusModel, calendarWindow: Binding<PlanWindow?>) -> some View {
        modifier(PicnicPlanSupport(status: status, calendarWindow: calendarWindow))
    }
}

/// "Saturday · 2 PM–5 PM" / "Vondelpark" / status line + planned score.
struct PicnicPlanRow: View {
    let plan: PicnicPlan
    let status: PlanStatus?

    var body: some View {
        let window = plan.window
        let ended = plan.isEnded()
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(PlanWindowRow.dayLabel(window)) · \(PlanWindowRow.rangeLabel(window))")
                    .font(.headline)
                    .monospacedDigit()
                Text(plan.spotName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                PlanStatusLabel(status: status, ended: ended, capReason: plan.serverCapReason)
                if plan.isSynced, !ended {
                    Label("Forecast alerts on", systemImage: "bell")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !ended {
                ScoreBadge(score: plan.scoreAtSave, diameter: 36)
            }
        }
        .opacity(ended ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(window: window, ended: ended)))
        .accessibilityIdentifier("picnicPlanRow")
    }

    private func accessibilityText(window: PlanWindow, ended: Bool) -> String {
        var parts = [PlanWindowRow.dayLabel(window), PlanWindowRow.rangeLabel(window), plan.spotName]
        if let text = PlanStatusLabel.text(status: status, ended: ended, capReason: plan.serverCapReason) {
            parts.append(text)
        }
        if plan.isSynced, !ended { parts.append(String(localized: "Forecast alerts on")) }
        if !ended { parts.append(String(localized: "planned score \(plan.scoreAtSave)")) }
        return parts.joined(separator: ", ")
    }
}

/// A followed plan (someone else's, from the server): same layout as
/// `PicnicPlanRow`, marked as shared, with the server's status.
struct FollowedPlanRow: View {
    let plan: ServerPlan

    var body: some View {
        let window = plan.window
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(PlanWindowRow.dayLabel(window)) · \(PlanWindowRow.rangeLabel(window))")
                    .font(.headline)
                    .monospacedDigit()
                Text(window.spotName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                PlanStatusLabel(status: plan.planStatus, ended: false, capReason: plan.capReason)
                Label("Shared with you", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let score = plan.score {
                ScoreBadge(score: score, diameter: 36)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(window)))
        .accessibilityIdentifier("followedPlanRow")
    }

    private func accessibilityText(_ window: PlanWindow) -> String {
        var parts = [PlanWindowRow.dayLabel(window), PlanWindowRow.rangeLabel(window), window.spotName,
                     String(localized: "Shared with you")]
        if let text = PlanStatusLabel.text(status: plan.planStatus, ended: false, capReason: plan.capReason) {
            parts.append(text)
        }
        if let score = plan.score { parts.append(String(localized: "score \(score)")) }
        return parts.joined(separator: ", ")
    }
}

/// "Still looks good" / "Not as good as when planned" / "Not recommended
/// now" (or "Rain expected" etc. when the server names the cap) / "Ended".
/// One status per plan: the server's when synced, else the local check.
struct PlanStatusLabel: View {
    let status: PlanStatus?
    var ended = false
    var capReason: String? = nil

    var body: some View {
        if let text = Self.text(status: status, ended: ended, capReason: capReason) {
            Label(text, systemImage: symbol)
                .font(.footnote)
                .foregroundStyle(color)
        }
    }

    static func text(status: PlanStatus?, ended: Bool, capReason: String?) -> String? {
        if ended { return String(localized: "Ended") }
        switch status {
        case .good: return String(localized: "Still looks good")
        case .worse: return String(localized: "Not as good as when planned")
        case .notRecommended:
            switch capReason {
            case "rain": return String(localized: "Rain expected")
            case "heat": return String(localized: "Too hot")
            case "cold": return String(localized: "Too cold")
            default: return String(localized: "Not recommended now")
            }
        case nil: return nil
        }
    }

    private var symbol: String {
        if ended { return "clock" }
        switch status {
        case .good: return "checkmark.circle"
        case .worse: return "arrow.down.right.circle"
        case .notRecommended, nil: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        if ended { return .secondary }
        switch status {
        case .good: return .brand
        case .worse, nil: return .secondary
        case .notRecommended: return .orange
        }
    }
}

/// "Plan It": saves the window as a picnic plan. Shows "Planned" once the
/// same spot and hour is saved.
struct PlanItButton: View {
    let window: PlanWindow
    let source: PicnicPlans.Source
    var onPlanned: () -> Void = {}

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var plans: [PicnicPlan]
    @State private var savedCount = 0

    private var isPlanned: Bool { PicnicPlans.contains(window, in: plans) }

    var body: some View {
        Button {
            guard PicnicPlans.add(window, existing: plans, context: context) else { return }
            savedCount += 1
            app.track("plan_created", ["source": .string(source.rawValue)])
            onPlanned()
        } label: {
            Label(isPlanned ? "Planned" : "Plan It",
                  systemImage: isPlanned ? "checkmark.circle.fill" : "calendar.badge.plus")
                .symbolEffect(.bounce, value: savedCount)
        }
        .disabled(isPlanned)
        .sensoryFeedback(.success, trigger: savedCount)
        .accessibilityIdentifier("planItButton")
    }
}

/// Navigation value: a spot opened at an hour (decision card, plans).
struct SpotHourLink: Hashable {
    let spotID: UUID
    let hour: Date
}
