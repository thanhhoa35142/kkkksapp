import Observation
import SwiftData
import SwiftUI

/// Scores for saved spots at the current hour — one batch call
/// (`GET /v1/spots?ids=`). Rows still render without scores if it fails.
@MainActor @Observable
final class SavedScoresModel {
    private(set) var scores: [UUID: ScoreSnapshot] = [:]

    func load(favorites: [FavoriteSpot], when: WhenSelection) async {
        let ids = favorites.map(\.spotID)
        guard !ids.isEmpty else { scores = [:]; return }
        do {
            let collection = try await AppConfig.apiClient.spots(ids: ids, when: when.apiDate)
            var result: [UUID: ScoreSnapshot] = [:]
            for f in collection.features {
                if let score = f.properties.score { result[f.properties.id] = score }
            }
            scores = result
        } catch {
            Log.api.error("saved scores failed: \(error.localizedDescription)")
        }
    }

    func summary(for favorite: FavoriteSpot) -> SpotSummary {
        SpotSummary(favorite, score: scores[favorite.spotID])
    }
}

/// S3 · Saved (iPhone tab). Drag to reorder in Edit mode; swipe to delete.
struct SavedScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \FavoriteSpot.sortIndex) private var favorites: [FavoriteSpot]
    @State private var model = SavedScoresModel()
    @State private var plan = WeekPlanModel()
    @State private var editingAlert: AlertRule?

    var body: some View {
        NavigationStack {
            List {
                if favorites.isEmpty {
                    ContentUnavailableView {
                        Label("No saved places", systemImage: "heart")
                    } description: {
                        Text("Tap Save on a spot to keep it here.")
                    }
                } else {
                    WeekPlanSection(favorites: favorites, plan: plan)
                    Section {
                        ForEach(favorites) { favorite in
                            let spot = model.summary(for: favorite)
                            NavigationLink(value: favorite.spotID) { SpotRow(spot: spot) }
                                .contextMenu { SpotContextMenu(spot: spot) }
                        }
                        .onMove(perform: move)
                        .onDelete(perform: delete)
                    } header: {
                        Text("Places · \(app.when.label)")
                    } footer: {
                        if !app.isPlus {
                            Text("\(favorites.count) of \(Favorites.freeLimit) on the Free plan")
                        }
                    }
                }
                AlertsSection(editing: $editingAlert)
            }
            .groupedList()
            .navigationTitle("Saved")
            .toolbar {
                #if os(iOS)
                if !favorites.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
                #endif
                ToolbarItem(placement: .primaryAction) { WhenMenu() }
            }
            .navigationDestination(for: UUID.self) { id in
                SpotDetailView(spotID: id)
            }
            .refreshable {
                await model.load(favorites: favorites, when: app.when)
                if app.isPlus { await plan.load(favorites: favorites) }
                await app.alerts.load()
            }
            .sheet(item: $editingAlert) { rule in
                AlertEditorSheet(editing: rule, app: app)
            }
            #if os(macOS)
            .onDeleteCommand {
                if let id = app.selectedSpotID, let index = favorites.firstIndex(where: { $0.spotID == id }) {
                    delete(at: IndexSet(integer: index))
                }
            }
            #endif
        }
        .task(id: TaskKey(ids: favorites.map(\.spotID), when: app.when)) {
            app.remember(favorites.map { model.summary(for: $0) })
            await model.load(favorites: favorites, when: app.when)
        }
        .task(id: PlanKey(ids: favorites.map(\.spotID), plus: app.isPlus)) {
            if app.isPlus { await plan.load(favorites: favorites) }
        }
    }

    private struct TaskKey: Equatable {
        let ids: [UUID]
        let when: WhenSelection
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = favorites
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in ordered.enumerated() { favorite.sortIndex = index }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(favorites[index]) }
    }
}

/// Saved › Alerts. Tap to edit, toggle to pause, swipe to delete.
struct AlertsSection: View {
    @Binding var editing: AlertRule?
    @Environment(AppState.self) private var app
    @State private var newArea: AreaDraft?
    @State private var areaUnavailable = false

    struct AreaDraft: Identifiable {
        let center: AreaPoint
        let name: String
        let timeZone: TimeZone
        var id: AreaPoint { center }
    }

    var body: some View {
        Section {
            if app.alerts.rules.isEmpty {
                Text("Open a spot and tap Alert, or get alerts for any spot near your place.")
                    .foregroundStyle(.secondary)
            }
            ForEach(app.alerts.rules) { rule in
                AlertRow(rule: rule, name: name(for: rule))
                    .contentShape(Rectangle())
                    .onTapGesture { editing = rule }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            Task { await app.alerts.delete(rule) }
                        }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = rule }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await app.alerts.delete(rule) }
                        }
                    }
            }
            Button {
                Task { await startAreaAlert() }
            } label: {
                Label("Add Area Alert", systemImage: "plus")
            }
            .sheet(item: $newArea) { draft in
                AlertEditorSheet(spotID: nil, spotName: draft.name, timeZone: draft.timeZone,
                                 existing: nil, areaCenter: draft.center)
            }
            .alert("Choose a place first", isPresented: $areaUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Area alerts cover the place you pick in Best Now.")
            }
        } header: {
            Text("Alerts")
        } footer: {
            if !app.isPlus {
                Text("The Free plan includes 1 alert.")
            }
        }
    }

    private func name(for rule: AlertRule) -> String {
        app.alerts.displayName(for: rule, summaries: app.summaries)
    }

    /// "Add Area Alert" — around the place Best Now uses (coarse point).
    private func startAreaAlert() async {
        guard let place = app.place, let c = await app.placeCoordinate() else {
            areaUnavailable = true
            return
        }
        // Alert hours are local to the area: a city's own zone, else this device's.
        var zone = TimeZone.current
        if case .city(let slug, _, _, _) = place,
           let tz = app.packs.first(where: { $0.slug == slug })?.tz,
           let cityZone = TimeZone(identifier: tz) {
            zone = cityZone
        }
        newArea = AreaDraft(center: AreaPoint(coarse: c.latitude, c.longitude), name: place.title, timeZone: zone)
    }
}
