import SwiftUI

/// S1 · Best Now — the screen the app opens on (iPhone).
struct BestNowScreen: View {
    @Environment(AppState.self) private var app
    @State private var model = BestNowModel()
    @State private var showCityPicker = false

    var body: some View {
        NavigationStack {
            List {
                BestNowRows(model: model, rowStyle: .push, showCityPicker: $showCityPicker,
                            showsAttribution: true)
            }
            .groupedList()
            // Empty / dark / failed: the system's full-screen state over an
            // empty list, not a card inside a row.
            .overlay {
                BestNowUnavailable(model: model, showCityPicker: $showCityPicker)
            }
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

/// Sections of the Best Now list. The first result is "the answer": its own
/// section, a larger ring and its time line; the rest follow under
/// "More nearby". `.push` = NavigationLink rows (iPhone); `.select` = tagged
/// rows for a `List(selection:)` (iPad/Mac sidebar), where empty / error
/// states are a compact inline section because the list holds more below.
struct BestNowRows: View {
    enum RowStyle { case push, select }

    let model: BestNowModel
    let rowStyle: RowStyle
    @Binding var showCityPicker: Bool
    var showsAttribution = false

    @Environment(AppState.self) private var app

    var body: some View {
        switch model.phase {
        case .idle, .loading:
            Section {
                ForEach(0..<3, id: \.self) { _ in
                    SpotRow(spot: Self.placeholder)
                        .redacted(reason: .placeholder)
                }
            }
        case .needsPlace:
            Section {
                ChoosePlaceRows(showCityPicker: $showCityPicker)
            }
        case .empty, .filteredOut, .dark, .failed:
            if rowStyle == .select {
                Section {
                    BestNowUnavailable(model: model, showCityPicker: $showCityPicker, inline: true)
                } header: {
                    Text("Best Now · \(app.when.label)")
                }
            }
        case .loaded:
            loadedSections
        }
    }

    @ViewBuilder
    private var loadedSections: some View {
        let rest = Array(model.items.dropFirst())
        let hasMore = !rest.isEmpty || model.mayHaveMore
        if let top = model.items.first {
            Section {
                row(top, isTop: true)
            } header: {
                Text("Top pick · \(app.when.label)")
            } footer: {
                if !hasMore && showsAttribution { AttributionFooter() }
            }
        }
        if hasMore {
            Section {
                ForEach(rest) { spot in
                    row(spot, isTop: false)
                }
                if model.mayHaveMore {
                    Button("See more picks with Plus") { app.paywall = .picks }
                }
            } header: {
                Text("More nearby")
            } footer: {
                if showsAttribution { AttributionFooter() }
            }
        }
    }

    @ViewBuilder
    private func row(_ spot: SpotSummary, isTop: Bool) -> some View {
        let content = SpotRow(
            spot: spot,
            timeLine: model.outlookText(for: spot),
            timeLineIsPositive: model.outlooks[spot.id]?.isPositive ?? true,
            badgeDiameter: isTop ? 56 : 44,
            identifier: isTop ? "spotRow.top" : "spotRow")
            // One motion when "When" changes: rows dim while loading and come
            // back with their new content, instead of every ring rolling while
            // rows jump. Opacity only, so it is Reduce Motion safe.
            .opacity(model.isRefreshing ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
        switch rowStyle {
        case .push:
            NavigationLink(value: spot.id) { content }
                .swipeActions(edge: .trailing) { SaveButton(spot: spot).tint(.brand) }
                .contextMenu { SpotContextMenu(spot: spot) }
        case .select:
            content
                .tag(spot.id)
                .contextMenu { SpotContextMenu(spot: spot) }
        }
    }

    private static let placeholder = SpotSummary(
        id: UUID(), kind: "park", name: "Placeholder park", names: [:], city: "City",
        tz: TimeZone.current.identifier, latitude: nil, longitude: nil,
        distanceM: 1200, score: nil)
}

/// Best Now's empty / filtered-out / dark / failed states. Full screen
/// (`ContentUnavailableView` as a list overlay) on the Best Now tab; a
/// compact text row in the sidebar (`inline`), where Saved and Alerts follow.
struct BestNowUnavailable: View {
    let model: BestNowModel
    @Binding var showCityPicker: Bool
    var inline = false

    @Environment(AppState.self) private var app

    private struct Content {
        let title: LocalizedStringKey
        let symbol: String
        let message: String
        let action: LocalizedStringKey
    }

    private var content: Content? {
        switch model.phase {
        case .empty:
            Content(title: "No spots here yet", symbol: "map",
                    message: String(localized: "Pickhour covers selected cities. Choose one to explore."),
                    action: "Browse Cities")
        case .filteredOut:
            Content(title: "No spots match your filters", symbol: "line.3.horizontal.decrease.circle",
                    message: String(localized: "Try fewer amenities or a lower minimum score."),
                    action: "Clear Filters")
        case .dark:
            Content(title: "It's dark out", symbol: "moon",
                    message: String(localized: "Scores pick up after sunrise."),
                    action: "Show Morning")
        case .failed(let message):
            Content(title: "Can't load spots", symbol: "wifi.slash", message: message, action: "Try Again")
        default:
            nil
        }
    }

    var body: some View {
        if let content {
            if inline {
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title).font(.headline)
                    Text(content.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(content.action, action: perform)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            } else {
                ContentUnavailableView {
                    Label(content.title, systemImage: content.symbol)
                } description: {
                    Text(content.message)
                } actions: {
                    Button(content.action, action: perform)
                }
            }
        }
    }

    private func perform() {
        switch model.phase {
        case .empty: showCityPicker = true
        case .filteredOut: app.setFilters(SpotFilters())
        case .dark: app.select(when: BestNowModel.nextMorning())
        case .failed: Task { await model.load(app: app) }
        default: break
        }
    }
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
