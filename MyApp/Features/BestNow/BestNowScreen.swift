import SwiftUI

/// S1 · Best Now — the screen the app opens on (iPhone).
struct BestNowScreen: View {
    @Environment(AppState.self) private var app
    @State private var model = BestNowModel()
    @State private var showCityPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BestNowRows(model: model, rowStyle: .push)
                } header: {
                    if model.phase == .loaded {
                        Text("Top picks · \(app.when.label)")
                    }
                } footer: {
                    AttributionFooter()
                }
            }
            .groupedList()
            .navigationTitle("Best Now")
            .refreshable { await model.load(app: app) }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    PlaceMenu(showCityPicker: $showCityPicker)
                }
                ToolbarItem(placement: .primaryAction) {
                    FilterButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    WhenMenu()
                }
            }
            .navigationDestination(for: UUID.self) { id in
                SpotDetailView(spotID: id)
            }
            .sheet(isPresented: $showCityPicker) {
                NavigationStack { CityPickerList { showCityPicker = false } }
            }
        }
        .task(id: ReloadKey(when: app.when, place: app.place, plus: app.isPlus, filters: app.filters)) {
            await model.load(app: app)
        }
    }
}

/// Rows of the Best Now list, including empty/error/upsell states.
/// `.push` = NavigationLink rows (iPhone); `.select` = tagged rows for a
/// `List(selection:)` (sidebar).
struct BestNowRows: View {
    enum RowStyle { case push, select }

    let model: BestNowModel
    let rowStyle: RowStyle

    @Environment(AppState.self) private var app
    @State private var showCityPicker = false

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ForEach(0..<3, id: \.self) { _ in
                    SpotRow(spot: Self.placeholder)
                        .redacted(reason: .placeholder)
                }
            case .needsPlace:
                ChoosePlaceRows(showCityPicker: $showCityPicker)
            case .empty:
                ContentUnavailableView {
                    Label("No spots here yet", systemImage: "map")
                } description: {
                    Text("Pickhour covers selected cities. Choose one to explore.")
                } actions: {
                    Button("Browse Cities") { showCityPicker = true }
                }
            case .filteredOut:
                ContentUnavailableView {
                    Label("No spots match your filters", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try fewer amenities or a lower minimum score.")
                } actions: {
                    Button("Clear Filters") { app.setFilters(SpotFilters()) }
                }
            case .dark:
                ContentUnavailableView {
                    Label("It's dark out", systemImage: "moon")
                } description: {
                    Text("Scores pick up after sunrise.")
                } actions: {
                    Button("Show Morning") { app.select(when: BestNowModel.nextMorning()) }
                }
            case .failed(let message):
                ContentUnavailableView {
                    Label("Can't load spots", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.load(app: app) } }
                }
            case .loaded:
                ForEach(model.items) { spot in
                    row(spot)
                }
                if model.mayHaveMore {
                    Button("See more picks with Plus") { app.paywall = .picks }
                }
            }
        }
        .sheet(isPresented: $showCityPicker) {
            NavigationStack { CityPickerList { showCityPicker = false } }
        }
    }

    @ViewBuilder
    private func row(_ spot: SpotSummary) -> some View {
        switch rowStyle {
        case .push:
            NavigationLink(value: spot.id) { SpotRow(spot: spot) }
                .swipeActions(edge: .trailing) { SaveButton(spot: spot).tint(.brand) }
                .contextMenu { SpotContextMenu(spot: spot) }
        case .select:
            SpotRow(spot: spot)
                .tag(spot.id)
                .contextMenu { SpotContextMenu(spot: spot) }
        }
    }

    private static let placeholder = SpotSummary(
        id: UUID(), kind: "park", name: "Placeholder park", names: [:], city: "City",
        tz: TimeZone.current.identifier, latitude: nil, longitude: nil,
        distanceM: 1200, score: nil)
}

/// First run / location denied: two plain choices, no modal (UI_SPEC S1).
struct ChoosePlaceRows: View {
    @Binding var showCityPicker: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where should we look?")
                .font(.headline)
            Text(app.location.isDenied
                 ? "Location is off for Pickhour. Choose a city, or turn it on in Settings."
                 : "Use your location while the app is open, or pick a city.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !app.location.isDenied {
                Button {
                    Task {
                        _ = await app.location.requestAuthorization()
                        if app.location.isAuthorized {
                            app.setPlace(.currentLocation)
                        }
                    }
                } label: {
                    Text("Use My Location").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Button {
                showCityPicker = true
            } label: {
                Text("Choose a City").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}

/// Long-press / right-click actions on a spot (UI.md context menus).
struct SpotContextMenu: View {
    let spot: SpotSummary
    @Environment(AppState.self) private var app

    var body: some View {
        Button("Show on Map", systemImage: "map") {
            app.selectedTab = .map
            app.open(spotID: spot.id, focusMap: true)
        }
        SaveButton(spot: spot)
        if let coordinate = spot.coordinate {
            Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                Directions.open(name: spot.displayName, coordinate: coordinate)
            }
        }
    }
}

/// ODbL requires OSM attribution wherever map data is shown.
struct AttributionFooter: View {
    var body: some View {
        Text("Map data © OpenStreetMap contributors")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
