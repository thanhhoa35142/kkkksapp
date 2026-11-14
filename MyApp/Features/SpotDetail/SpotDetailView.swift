import MapKit
import SwiftUI

/// S5 · Spot Detail. Pushed from lists, shown in a sheet from the iPhone map
/// and in the inspector / sidebar on iPad and Mac.
///
/// The name and the score each appear once per context (no nav-bar title:
/// long names need two lines). The map sheet's first ~220 pt is a pinned
/// summary — name, score, Directions — so the peek detent answers the
/// question on its own; the rest scrolls under it when expanded.
struct SpotDetailView: View {
    enum Context {
        /// Pushed from a list: static header map + summary.
        case page
        /// iPad / Mac inspector or sidebar push: the live map is already beside it.
        case inspector
        /// iPhone map sheet (220 pt peek): pinned summary header, no nav bar.
        case mapSheet

        var showsHeaderMap: Bool { self == .page }
    }

    let spotID: UUID
    var context: Context = .page

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = SpotDetailModel()
    @State private var day: Date?
    @State private var showBreakdown = false
    @State private var showReport = false
    @State private var showAlertEditor = false
    @State private var isNearSpot = false
    /// Spot whose score has drawn in once (M3). Others start from 0.
    @State private var introSpotID: UUID?
    @State private var reportSent = false
    @State private var alertSaves = 0

    private var summary: SpotSummary? { app.summaries[spotID] }

    private var timeZone: TimeZone {
        detailTimeZone ?? summary?.timeZone ?? .current
    }

    private var detailTimeZone: TimeZone? {
        model.detail.flatMap { TimeZone(identifier: $0.tz) }
    }

    /// The hour this screen shows: chart selection, else the app's "When".
    private var activeHour: Date { model.selectedHour ?? app.when.resolved }

    private var activePoint: ForecastPoint? { model.point(at: activeHour) }

    private var score: Int? { activePoint?.score ?? summary?.score?.score }

    /// M3: the number and ring count up from 0 once per spot open;
    /// Reduce Motion shows the value straight away.
    private var shownScore: Int? {
        guard let score else { return nil }
        return reduceMotion || introSpotID == spotID ? score : 0
    }

    private var displayName: String {
        if let d = model.detail {
            return NameResolver.displayName(names: d.names, fallback: d.name, kind: d.kind, city: d.city)
        }
        return summary?.displayName ?? ""
    }

    private var hasAlert: Bool { app.alerts.rule(for: spotID) != nil }

    var body: some View {
        List {
            if context != .mapSheet {
                headerSection
            }
            scoreSection
            if isNearSpot {
                CrowdReportSection(spotID: spotID)
            }
            forecastSection
            amenitiesSection
            aboutSection
        }
        .groupedList()
        .safeAreaInset(edge: .top, spacing: 0) {
            if context == .mapSheet {
                sheetHeader
            }
        }
        .navigationTitle(Text(verbatim: ""))
        .inlineTitle()
        .hidesNavigationBar(context == .mapSheet)
        .toolbar {
            if context != .mapSheet, let spot = currentSummary {
                ToolbarItem(placement: .primaryAction) { SaveButton(spot: spot) }
                if let url = shareURL {
                    ToolbarItem(placement: .primaryAction) { shareLink(url) }
                }
            }
        }
        .overlay {
            if case .failed(let message) = model.phase {
                ContentUnavailableView {
                    Label("Can't load this spot", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.load(id: spotID) } }
                }
            }
        }
        .task(id: spotID) {
            model.selectedHour = nil
            day = nil
            isNearSpot = false
            reportSent = false
            await model.load(id: spotID)
            app.track("spot_opened", ["kind": .string(model.detail?.kind ?? summary?.kind ?? "")])
            isNearSpot = await CrowdProximity.check(app: app, spot: coordinate,
                                                    kind: model.detail?.kind ?? summary?.kind ?? "")
        }
        .task(id: IntroKey(spotID: spotID, ready: score != nil)) {
            // Runs after the first frame (at 0), so the change animates.
            guard score != nil, introSpotID != spotID else { return }
            introSpotID = spotID
        }
        .sheet(isPresented: $showBreakdown) {
            if let point = activePoint {
                ScoreBreakdownSheet(spotID: spotID, point: point, timeZone: timeZone)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(spotID: spotID) { reportSent = true }
        }
        .sheet(isPresented: $showAlertEditor) {
            AlertEditorSheet(spotID: spotID, spotName: displayName, timeZone: timeZone,
                             existing: app.alerts.rule(for: spotID),
                             onSaved: { alertSaves += 1 })
        }
    }

    private struct IntroKey: Equatable {
        let spotID: UUID
        let ready: Bool
    }

    // MARK: Header

    /// Page / inspector: optional static map, then name and subtitle.
    @ViewBuilder
    private var headerSection: some View {
        Section {
            if context.showsHeaderMap && !dynamicTypeSize.isAccessibilitySize, let coordinate = coordinate {
                HeaderMap(coordinate: coordinate, area: model.detail?.area)
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    /// iPhone map sheet: everything the 220 pt peek needs, pinned above the
    /// list — name + subtitle (with Save / Share), score + tier, Directions.
    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let spot = currentSummary {
                    SaveButton(spot: spot)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                    if let url = shareURL {
                        shareLink(url)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                    }
                }
            }
            scoreLine(compact: true)
            actionButtons
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.groupedBackground)
    }

    // MARK: Score

    @ViewBuilder
    private var scoreSection: some View {
        Section {
            if context != .mapSheet {
                scoreLine(compact: false)
            }
            if let weather = activePoint?.weather, weather.hasValues {
                HourWeatherRow(weather: weather)
            }
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                Label(ReasonLocalizer.text(for: reason),
                      systemImage: ReasonLocalizer.symbol(for: reason.code) ?? "info.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            if let score, activePoint != nil {
                Button("Why \(score)?") { showBreakdown = true }
            }
            if context != .mapSheet {
                actionButtons
            }
        }
    }

    /// "82 Great" once, as a number and a label; the ring beside it carries
    /// no number (it would repeat the score).
    private func scoreLine(compact: Bool) -> some View {
        let confidence = activePoint?.confidence ?? summary?.score?.confidence
        let cap = activePoint?.capReason ?? summary?.score?.capReason
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let shownScore, let score {
                        Text(shownScore, format: .number)
                            .font(.system(compact ? .title : .largeTitle, design: .rounded).bold())
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(shownScore)))
                            .animation(.smooth(duration: 0.3), value: shownScore)
                        Text(ScoreTier(score: score).label)
                            .font(.headline)
                            .foregroundStyle(ScoreTier(score: score).color)
                        if compact {
                            // Peek: one line, "82 Great · Today 3 PM".
                            Text(verbatim: "· \(Format.dayHour(activeHour, in: timeZone))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No forecast yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                if !compact {
                    Text(scoreCaption(confidence: confidence))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if !compact {
                ScoreBadge(score: shownScore, capReason: cap, diameter: 56, showsNumber: false,
                           animatesChanges: true, motionDuration: 0.3, maxTypeScale: 1.2)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Directions is the one prominent action; Alert is secondary. Reporting
    /// lives in About ("Is this spot still here?"). Stacked at accessibility
    /// sizes so labels never get cut.
    private var actionButtons: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if let coordinate {
                Button {
                    Directions.open(name: displayName, coordinate: coordinate)
                    app.track("directions_opened")
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("spotAction.directions")
            }
            Button {
                showAlertEditor = true
            } label: {
                Label(hasAlert ? "Edit Alert" : "Alert", systemImage: hasAlert ? "bell.fill" : "bell")
                    // M5: the bell confirms a saved alert where the user lands.
                    .symbolEffect(.bounce, value: alertSaves)
                    .frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("spotAction.alert")
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 4)
    }

    // MARK: Sections

    @ViewBuilder
    private var forecastSection: some View {
        let days = model.days(in: timeZone)
        if !days.isEmpty {
            Section {
                let selectedDay = day ?? days[0]
                WeekStrip(
                    days: WeekStrip.days(from: days,
                                         points: { model.points(on: $0, in: timeZone) },
                                         locked: dayNeedsPlus),
                    timeZone: timeZone,
                    selected: selectedDay,
                    onSelect: select)
                    .padding(.vertical, 2)

                HourlyScoreChart(
                    points: model.points(on: selectedDay, in: timeZone),
                    timeZone: timeZone,
                    selectedHour: $model.selectedHour,
                    activeHour: activeHour)
                    .padding(.vertical, 4)
            } header: {
                Text("Next 7 days")
            } footer: {
                if app.isPlus {
                    Text("Drag across the chart to check another hour. Shaded hours are after dark.")
                } else {
                    Text("Best score of each day. Hourly detail after tomorrow comes with Plus. Shaded hours are after dark.")
                }
            }
        }
    }

    @ViewBuilder
    private var amenitiesSection: some View {
        let amenities = nearestAmenities
        if !amenities.isEmpty {
            Section("Amenities") {
                ForEach(amenities, id: \.type) { amenity in
                    LabeledContent {
                        Text(Format.distance(meters: Double(amenity.distanceM)))
                            .monospacedDigit()
                    } label: {
                        Label(AmenityStyle.label(amenity.type), systemImage: AmenityStyle.symbol(amenity.type))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            if let verified = model.detail?.lastVerifiedAt {
                LabeledContent("Last verified") {
                    Text(verified, format: .dateTime.day().month().year())
                }
            }
            LabeledContent("Source", value: "OpenStreetMap")
            if reportSent {
                HStack(spacing: 8) {
                    ConfirmationMark()
                    Text("Thanks. Your report was sent.")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else {
                Button("Is this spot still here?") { showReport = true }
                    .accessibilityIdentifier("spotAction.report")
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Map data © OpenStreetMap contributors.")
                WeatherAttribution(source: model.detail?.weatherSource)
            }
        }
    }

    // MARK: Helpers

    private var coordinate: CLLocationCoordinate2D? {
        model.detail?.coordinate ?? summary?.coordinate
    }

    private var currentSummary: SpotSummary? {
        if let summary { return summary }
        guard let d = model.detail else { return nil }
        return SpotSummary(id: d.id, kind: d.kind, name: d.name, names: d.names, city: d.city, tz: d.tz,
                           latitude: d.coordinate?.latitude, longitude: d.coordinate?.longitude,
                           distanceM: nil, score: nil)
    }

    private var headerSubtitle: String {
        let kind = model.detail?.kind ?? summary?.kind ?? ""
        var parts = [KindStyle.label(kind)]
        if let distance = summary?.distanceM { parts.append(Format.distance(meters: distance)) }
        if let city = model.detail?.city ?? summary?.city { parts.append(city) }
        return parts.joined(separator: " · ")
    }

    private var reasons: [Reason] {
        let source = activePoint?.reasons ?? summary?.score?.reasons ?? []
        return Array(source.filter { ReasonLocalizer.isKnown($0.code) }.prefix(3))
    }

    private func scoreCaption(confidence: Int?) -> String {
        let hour = Format.dayHour(activeHour, in: timeZone)
        guard let confidence else { return hour }
        return "\(hour) · \(Format.confidence(confidence))"
    }

    /// Nearest amenity per type.
    private var nearestAmenities: [SpotDetail.Amenity] {
        var best: [String: SpotDetail.Amenity] = [:]
        for a in model.detail?.amenities ?? [] where (best[a.type]?.distanceM ?? .max) > a.distanceM {
            best[a.type] = a
        }
        return best.values.sorted { $0.distanceM < $1.distanceM }
    }

    private var mapsURL: URL? {
        guard let c = coordinate else { return nil }
        return SpotLink.mapsURL(name: displayName, latitude: c.latitude, longitude: c.longitude)
    }

    /// The Pickhour share page (`<ShareBaseURL>/s/<id>`, opens the app when
    /// installed); the Apple Maps link when no share host is configured.
    private var shareURL: URL? {
        SpotLink.shareURL(spotID: spotID) ?? mapsURL
    }

    /// Shares the link with a line of context:
    /// "Vondelpark · Today 3 PM · score 82".
    private func shareLink(_ url: URL) -> some View {
        ShareLink(item: url, subject: Text(displayName), message: Text(shareMessage))
    }

    private var shareMessage: String {
        let hour = Format.dayHour(activeHour, in: timeZone)
        guard let score else { return "\(displayName) · \(hour)" }
        return String(localized: "\(displayName) · \(hour) · score \(score)")
    }

    /// Free plan: hourly detail for today and tomorrow; days 3+ need Plus (spec §15).
    private func dayNeedsPlus(_ index: Int) -> Bool {
        !app.isPlus && index >= 2
    }

    private func select(_ entry: WeekStrip.Day) {
        if entry.locked {
            // The day's best hour is Free data (week strip) — show it on the paywall.
            app.paywallTeaser = entry.best.map {
                ForecastTeaser(day: entry.date, hour: $0.tsHour, score: $0.score, timeZone: timeZone)
            }
            app.paywall = .forecast
        } else if entry.date != day {
            day = entry.date
            model.selectedHour = nil
        }
    }
}

/// Static map with the park outline — stands in for a photo (UI_SPEC S5).
private struct HeaderMap: View {
    let coordinate: CLLocationCoordinate2D
    let area: JSONValue?

    var body: some View {
        let rings = GeoJSONArea.outerRings(area)
        Map(initialPosition: .region(region(rings)), interactionModes: []) {
            ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                MapPolygon(coordinates: ring)
                    .foregroundStyle(Color.brand.opacity(0.15))
                    .stroke(Color.brand, lineWidth: 1.5)
            }
            if rings.isEmpty {
                Marker("", coordinate: coordinate)
                    .tint(Color.brand)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .accessibilityHidden(true)
    }

    private func region(_ rings: [[CLLocationCoordinate2D]]) -> MKCoordinateRegion {
        let all = rings.flatMap { $0 }
        guard let minLat = all.map(\.latitude).min(), let maxLat = all.map(\.latitude).max(),
              let minLon = all.map(\.longitude).min(), let maxLon = all.map(\.longitude).max() else {
            return MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.003),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.003))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// Weather attribution required by Apple WeatherKit / Open-Meteo (CC BY 4.0).
struct WeatherAttribution: View {
    let source: String?

    private static let appleWeatherLegal = URL(string: "https://weatherkit.apple.com/legal-attribution.html")
        ?? URL(fileURLWithPath: "/")
    private static let openMeteo = URL(string: "https://open-meteo.com/") ?? URL(fileURLWithPath: "/")

    var body: some View {
        switch source {
        case "weatherkit":
            HStack(spacing: 4) {
                Text("Weather:")
                Link("Apple Weather", destination: Self.appleWeatherLegal)
            }
        case "openmeteo":
            HStack(spacing: 4) {
                Text("Weather:")
                Link("Open-Meteo.com", destination: Self.openMeteo)
            }
        default:
            EmptyView()
        }
    }
}

/// Weather for the hour on screen: temperature, rain chance and wind as three
/// plain columns (no icons — the reason rows below already carry them).
/// Accessibility sizes stack them as labelled rows.
private struct HourWeatherRow: View {
    let weather: ForecastPoint.Weather

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var items: [Item] {
        var result: [Item] = []
        if let temp = weather.tempC {
            result.append(Item(label: String(localized: "Temperature"), value: Format.temperature(celsius: temp)))
        }
        if let feels = weather.feelsLikeC, let temp = weather.tempC, abs(feels - temp) >= 2 {
            result.append(Item(label: String(localized: "Feels like"), value: Format.temperature(celsius: feels)))
        }
        if let rain = weather.precipProb {
            result.append(Item(label: String(localized: "Rain"), value: "\(rain)%"))
        }
        if let wind = weather.windKmh {
            result.append(Item(label: String(localized: "Wind"), value: Format.wind(kmh: wind)))
        }
        return result
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ForEach(items) { item in
                LabeledContent(item.label, value: item.value)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.value)
                            .font(.headline)
                            .monospacedDigit()
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(item.label): \(item.value)"))
                }
            }
            .padding(.vertical, 2)
        }
    }
}

extension ForecastPoint.Weather {
    /// Something to show in the weather row.
    var hasValues: Bool { tempC != nil || precipProb != nil || windKmh != nil }
}
