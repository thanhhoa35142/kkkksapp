import Observation
import SwiftUI

/// Thursday-evening "your weekend plan" push for the saved places (Plus).
/// The server owns the schedule; the app only sends the place list.
@MainActor @Observable
final class WeekendDigestModel {
    private(set) var enabled = false
    private(set) var isBusy = false
    private(set) var isLoaded = false
    private var sentIDs: Set<UUID> = []

    private var api: APIClient { AppConfig.apiClient }

    func load() async {
        guard !isLoaded else { return }
        do {
            let digest = try await api.weeklyDigest(deviceID: DeviceIdentity.deviceID)
            enabled = digest?.enabled ?? false
            sentIDs = Set(digest?.spotIds ?? [])
            isLoaded = true
        } catch {
            Log.api.error("digest load failed: \(error.localizedDescription)")
        }
    }

    /// Toggle. Turning on asks for notification permission first.
    func set(_ on: Bool, spotIDs: [UUID], app: AppState) async {
        isBusy = true
        defer { isBusy = false }
        if on {
            let granted = await PushManager.shared.requestAuthorization()
            if granted { await PushManager.shared.registerIfAuthorized() }
        }
        let previous = enabled
        enabled = on
        do {
            let digest = try await api.setWeeklyDigest(deviceID: DeviceIdentity.deviceID, spotIDs: spotIDs, enabled: on)
            sentIDs = Set(digest.spotIds)
            app.track(on ? "digest_enabled" : "digest_disabled")
        } catch let error as APIError where error.code == "plan_limit" {
            enabled = previous
            app.paywall = .planner
        } catch {
            enabled = previous
            Log.api.error("digest save failed: \(error.localizedDescription)")
        }
    }

    /// Keeps the server's list in step with Saved while the push is on.
    func sync(spotIDs: [UUID]) async {
        guard isLoaded, enabled, !isBusy, Set(spotIDs) != sentIDs, !spotIDs.isEmpty else { return }
        do {
            let digest = try await api.setWeeklyDigest(deviceID: DeviceIdentity.deviceID, spotIDs: spotIDs, enabled: true)
            // Merged spots come back under their new id — remember the
            // request too so we don't resend on every appearance.
            sentIDs = Set(digest.spotIds).union(spotIDs)
        } catch {
            Log.api.error("digest sync failed: \(error.localizedDescription)")
        }
    }
}

/// Reload trigger for the plan: Saved list changed or plan changed.
struct PlanKey: Equatable {
    let ids: [UUID]
    let plus: Bool
}

/// S3 › This Week — best window of each day across saved places (Plus).
/// Free sees one locked row that opens the paywall (`reason: planner`).
/// Used in the Saved tab (push) and the iPad/Mac sidebar (select).
struct WeekPlanSection: View {
    let favorites: [FavoriteSpot]
    let plan: WeekPlanModel
    var rowStyle: BestNowRows.RowStyle = .push

    @Environment(AppState.self) private var app
    @State private var digest = WeekendDigestModel()

    private var spotIDs: [UUID] { favorites.map(\.spotID) }

    var body: some View {
        Section {
            if app.isPlus {
                plusContent
            } else {
                Button {
                    app.paywall = .planner
                } label: {
                    Label("See the best times this week", systemImage: "lock.fill")
                }
            }
        } header: {
            Text("This Week")
        } footer: {
            if app.isPlus, favorites.count > WeekPlanModel.maxSpots {
                Text("Planned from your first \(WeekPlanModel.maxSpots) places.")
            } else if !app.isPlus {
                Text("Plus finds the best 2–4 hours of each day across your saved places.")
            }
        }
    }

    @ViewBuilder
    private var plusContent: some View {
        switch plan.phase {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .accessibilityLabel(Text("Loading this week's plan"))
        case .failed:
            Text("Couldn't load this week's plan.")
                .foregroundStyle(.secondary)
        case .loaded:
            if plan.days.isEmpty {
                Text("No 2-hour window scores 60 or more at your saved places this week.")
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.days) { window in
                row(window)
            }
        }
        Toggle(isOn: Binding(
            get: { digest.enabled },
            set: { on in Task { await digest.set(on, spotIDs: spotIDs, app: app) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekend plan on Thursday")
                Text("A notification with the best weekend window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(digest.isBusy || !digest.isLoaded)
        .task(id: spotIDs) {
            await digest.load()
            await digest.sync(spotIDs: spotIDs)
        }
    }

    @ViewBuilder
    private func row(_ window: PlanWindow) -> some View {
        switch rowStyle {
        case .push:
            NavigationLink(value: window.spotID) { PlanWindowRow(window: window) }
                .simultaneousGesture(TapGesture().onEnded { app.track("plan_opened") })
        case .select:
            PlanWindowRow(window: window)
                .tag(window.spotID)
        }
    }
}

/// "Saturday" / "2 PM–6 PM · Vondelpark" + score ring.
struct PlanWindowRow: View {
    let window: PlanWindow

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day)
                    .font(.headline)
                Text("\(range) · \(window.spotName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            ScoreBadge(score: window.score, diameter: 36)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(day), \(range), \(window.spotName), score \(window.score)"))
    }

    private var range: String {
        "\(Format.hour(window.start, in: window.timeZone))–\(Format.hour(window.end, in: window.timeZone))"
    }

    /// "Today", "Tomorrow", else the full weekday in the spot's time zone.
    private var day: String {
        var calendar = Calendar.current
        calendar.timeZone = window.timeZone
        if calendar.isDateInToday(window.start) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(window.start) { return String(localized: "Tomorrow") }
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.timeZone = window.timeZone
        return window.start.formatted(style)
    }
}
