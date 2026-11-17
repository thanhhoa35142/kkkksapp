import SwiftUI

/// S1 · Best Now — the screen the app opens on (iPhone).
struct BestNowScreen: View {
    @Environment(AppState.self) private var app
    @State private var model = BestNowModel()
    @State private var showCityPicker = false

    var body: some View {
        NavigationStack {
            List {
                BestNowRows(model: model, rowStyle: .push, showCityPicker: $showCityPicker)
            }
            .groupedList()
            // Empty / dark / failed: the system's full-screen state over an
            // empty list, not a card inside a row.
            .overlay {
                BestNowUnavailable(model: model, showCityPicker: $showCityPicker)
            }
            .navigationTitle("Best Now")
            .refreshable { await model.load(app: app, forceWeather: true) }
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
            .navigationDestination(for: SpotHourLink.self) { link in
                SpotDetailView(spotID: link.spotID, focusHour: link.hour)
            }
            .sheet(isPresented: $showCityPicker, onDismiss: { app.presentDeferredPaywall() }) {
                NavigationStack { CityPickerList(showsGetaways: true) { showCityPicker = false } }
            }
            .getawaysSheet()
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

    @Environment(AppState.self) private var app

    var body: some View {
        if showsWeather {
            NearbyWeatherSection(points: model.weather, placeName: placeName, when: app.when.resolved,
                                 timeZone: weatherTimeZone)
                .opacity(model.isRefreshing ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
        }
        phaseSections
    }

    /// Weather rides along with rows that are on screen: not on the first-run
    /// place prompt, and not under the full-screen empty / failed states.
    private var showsWeather: Bool {
        // Hidden when the selected hour is past the 48 h forecast.
        guard NearbyWeatherPoint.point(at: app.when.resolved, in: model.weather) != nil else { return false }
        switch model.phase {
        case .loading, .loaded: return true
        case .dark: return model.decision != nil
        default: return false
        }
    }

    /// nil = the user's own location ("Weather near you").
    private var placeName: String? {
        if case .city(_, let name, _, _) = app.place { return name }
        return nil
    }

    /// Hour labels in the place's time zone: a city's own (from its spots),
    /// else the device's.
    private var weatherTimeZone: TimeZone {
        if case .city = app.place { return model.items.first?.timeZone ?? .current }
        return .current
    }

    @ViewBuilder
    private var phaseSections: some View {
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
        case .dark where model.decision != nil:
            // After sunset: no "It's dark out" dead end when a later window
            // exists — the card says when to go.
            loadedSections
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
            if let city = model.weekendHint.city {
                GetawaysHintSection(city: city)
            }
        }
    }

    @ViewBuilder
    private var loadedSections: some View {
        let rest = model.remainingItems
        let hasMore = !rest.isEmpty || model.mayHaveMore
        if let decision = model.decision, let spot = model.decisionSpot {
            DecisionSection(decision: decision, spot: spot, reasons: model.decisionReasons(),
                            rowStyle: rowStyle)
                .opacity(model.isRefreshing ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
        } else if let top = model.items.first {
            Section {
                row(top, isTop: true)
            } header: {
                Text("Top pick · \(app.when.label)")
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

/// "Weather near you": the selected hour's numbers, then the next 12 hours as
/// a compact strip. Plain rows of a grouped list, no `NavigationLink` and no
/// tag, so it is never selectable in the sidebar.
struct NearbyWeatherSection: View {
    let points: [NearbyWeatherPoint]
    /// nil = the user's location.
    let placeName: String?
    let when: Date
    let timeZone: TimeZone

    private static let stripHours = 12

    var body: some View {
        Section {
            if let selected = NearbyWeatherPoint.point(at: when, in: points), selected.hasValues {
                HourWeatherRow(point: selected)
            }
            let strip = NearbyWeatherPoint.strip(from: when, in: points, count: Self.stripHours)
            if strip.count > 1 {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(strip) { point in
                            WeatherHourColumn(point: point, timeZone: timeZone)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("weather.strip")
            }
        } header: {
            if let placeName {
                Text("Weather in \(placeName)")
            } else {
                Text("Weather near you")
            }
        }
    }
}

/// One hour of the strip: "4 PM", symbol, "21°", rain chance when it matters.
/// Read as a single element ("4 PM, 21°, rain 30%").
private struct WeatherHourColumn: View {
    let point: NearbyWeatherPoint
    let timeZone: TimeZone

    /// Rain chance worth a line of its own.
    private static let rainThreshold = 20

    private var hourLabel: String {
        NearbyWeatherPoint.isCurrentHour(point.ts) ? String(localized: "Now") : Format.hour(point.ts, in: timeZone)
    }

    private var temperature: String? {
        point.tempC.map { Format.temperature(celsius: $0) }
    }

    private var rain: Int? {
        guard let chance = point.precipProb, chance >= Self.rainThreshold else { return nil }
        return chance
    }

    private var accessibilityText: String {
        var parts = [hourLabel]
        if let temperature { parts.append(temperature) }
        if let rain { parts.append(String(localized: "rain \(rain)%")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: hourLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: point.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(height: 26)
                .accessibilityHidden(true)
            Text(verbatim: temperature ?? "–")
                .font(.subheadline)
                .monospacedDigit()
            if let rain {
                Text(verbatim: "\(rain)%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}

/// The decision card: "Today · Vondelpark · 4 PM–6 PM", why, and two
/// actions (Plan It, Share). Row 1 opens the spot at the window's start;
/// row 2 holds the buttons so a tap on one never triggers the other.
struct DecisionSection: View {
    let decision: PicnicDecision
    let spot: SpotSummary
    let reasons: [Reason]
    let rowStyle: BestNowRows.RowStyle

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var window: PlanWindow { decision.window }

    var body: some View {
        Section {
            summaryRow
                .task(id: decision.id) {
                    app.track("decision_shown", ["startsNow": .bool(decision.startsAtSelectedHour)])
                }
            actionsRow
        } header: {
            Text(decision.startsAtSelectedHour
                 ? String(localized: "Best plan · \(app.when.label)")
                 : String(localized: "Next good time"))
        } footer: {
            if !decision.startsAtSelectedHour {
                Text("Not a great time for a picnic nearby. This is the next good one.")
            }
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        switch rowStyle {
        case .push:
            NavigationLink(value: SpotHourLink(spotID: window.spotID, hour: window.start)) { summary }
                .simultaneousGesture(TapGesture().onEnded { app.track("decision_tapped") })
                .contextMenu { SpotContextMenu(spot: spot) }
        case .select:
            // The sidebar list selects by spot id; a button carries the hour.
            Button {
                app.track("decision_tapped")
                app.open(spotID: window.spotID, at: window.start, focusMap: true)
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .contextMenu { SpotContextMenu(spot: spot) }
        }
    }

    /// Sentence, place, reasons and the window's score as one element.
    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Explicit limits: a Mac sidebar row truncates to one line
                // by default ("Today · Vondelpark · 10 AM–…").
                Text(verbatim: sentence)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(spot.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !reasonText.isEmpty {
                    Text(verbatim: reasonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            ScoreBadge(score: window.score, diameter: 44)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("spotRow.top")
    }

    /// Two bordered buttons; stacked at accessibility sizes.
    private var actionsRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            PlanItButton(window: window, source: .decision) {
                app.track("decision_planned")
            }
            ShareLink(item: PicnicPlans.link(for: window), subject: Text(window.spotName),
                      message: Text(window.shareText)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            // No completion callback on ShareLink: this counts sheet opens.
            .simultaneousGesture(TapGesture().onEnded {
                app.track("plan_shared", ["source": .string(PicnicPlans.Source.decision.rawValue)])
            })
        }
        .buttonStyle(.bordered)
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 2)
    }

    /// "Today · Vondelpark · 4 PM–6 PM" (spot-local day and hours).
    private var sentence: String {
        "\(PlanWindowRow.dayLabel(window)) · \(window.spotName) · \(PlanWindowRow.rangeLabel(window))"
    }

    private var reasonText: String {
        reasons.map { ReasonLocalizer.text(for: $0) }.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [PlanWindowRow.dayLabel(window), window.spotName, PlanWindowRow.rangeLabel(window),
                     String(localized: "score \(window.score)")]
        if !reasonText.isEmpty { parts.append(reasonText) }
        return parts.joined(separator: ", ")
    }
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
        case .dark where model.decision == nil:
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

