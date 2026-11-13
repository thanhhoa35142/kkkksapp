import SwiftData
import SwiftUI

/// iPad, Mac, unfolded foldables: Explore = list + map side by side
/// (UI_SPEC §10.2). Medium width pushes the detail inside the sidebar;
/// wide (≥ 1000 pt) shows it in a trailing inspector next to the map.
struct RegularRoot: View {
    @Environment(AppState.self) private var app

    private static let wideBreakpoint: CGFloat = 1000

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.wideBreakpoint
            NavigationSplitView {
                ExploreSidebar(pushesDetail: !wide)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
            } detail: {
                ExploreMap()
                    .inspector(isPresented: inspectorBinding(enabled: wide)) {
                        if let id = app.selectedSpotID {
                            NavigationStack {
                                SpotDetailView(spotID: id, showsHeaderMap: false)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Close") { app.selectedSpotID = nil }
                                        }
                                    }
                            }
                            .inspectorColumnWidth(min: 320, ideal: 360, max: 440)
                        }
                    }
            }
        }
    }

    private func inspectorBinding(enabled: Bool) -> Binding<Bool> {
        Binding(
            get: { enabled && app.selectedSpotID != nil },
            set: { if !$0 { app.selectedSpotID = nil } }
        )
    }
}

/// Sidebar: Best Now results and Saved spots in one list. Selecting a row
/// selects the spot everywhere (map pin + detail).
private struct ExploreSidebar: View {
    let pushesDetail: Bool

    @Environment(AppState.self) private var app
    @State private var bestNow = BestNowModel()
    @State private var saved = SavedScoresModel()
    @State private var plan = WeekPlanModel()
    @State private var showSettings = false
    @State private var showCityPicker = false
    @State private var editingAlert: AlertRule?
    @Query(sort: \FavoriteSpot.sortIndex) private var favorites: [FavoriteSpot]

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            List(selection: $app.selectedSpotID) {
                Section {
                    BestNowRows(model: bestNow, rowStyle: .select)
                } header: {
                    Text("Best Now · \(app.when.label)")
                }
                if !favorites.isEmpty {
                    WeekPlanSection(favorites: favorites, plan: plan, rowStyle: .select)
                    Section("Saved") {
                        ForEach(favorites) { favorite in
                            SpotRow(spot: saved.summary(for: favorite))
                                .tag(favorite.spotID)
                        }
                    }
                }
                AlertsSection(editing: $editingAlert)
                Section {
                    AttributionFooter()
                }
            }
            .navigationTitle("Explore")
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    PlaceMenu(showCityPicker: $showCityPicker)
                }
                ToolbarItem(placement: .primaryAction) {
                    WhenMenu()
                }
                ToolbarItem(placement: .primaryAction) {
                    FilterButton()
                }
                #if os(iOS)
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                }
                #endif
            }
            .navigationDestination(item: pushBinding) { id in
                SpotDetailView(spotID: id, showsHeaderMap: false)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsScreen()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
            .sheet(item: $editingAlert) { rule in
                AlertEditorSheet(editing: rule, app: app)
            }
            .sheet(isPresented: $showCityPicker) {
                NavigationStack { CityPickerList { showCityPicker = false } }
                    .frame(minWidth: 360, minHeight: 480)
            }
        }
        .task(id: ReloadKey(when: app.when, place: app.place, plus: app.isPlus, filters: app.filters)) { await reload() }
        .task(id: favorites.map(\.spotID)) { await saved.load(favorites: favorites, when: app.when) }
        .task(id: PlanKey(ids: favorites.map(\.spotID), plus: app.isPlus)) {
            if app.isPlus { await plan.load(favorites: favorites) }
        }
        .onChange(of: app.selectedSpotID) { _, _ in app.mapFocusVersion += 1 }
    }

    /// Medium width: selection pushes the detail inside this column.
    private var pushBinding: Binding<UUID?> {
        Binding(
            get: { pushesDetail ? app.selectedSpotID : nil },
            set: { if $0 == nil { app.selectedSpotID = nil } }
        )
    }

    private func reload() async {
        await bestNow.load(app: app)
        await saved.load(favorites: favorites, when: app.when)
    }
}

/// Map column of Explore — selection lives in AppState (no sheet).
private struct ExploreMap: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        MapContainer(selection: $app.selectedSpotID)
    }
}

struct ReloadKey: Equatable {
    let when: WhenSelection
    let place: Place?
    let plus: Bool
    var filters = SpotFilters()
}
