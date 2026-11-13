import MapKit
import SwiftUI

/// S5 · Spot Detail. Pushed from lists, shown in a sheet from the iPhone map
/// and in the inspector / sidebar on iPad and Mac.
struct SpotDetailView: View {
    let spotID: UUID
    /// Off when the live map is already behind (map sheet, inspector).
    var showsHeaderMap = true

    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = SpotDetailModel()
    @State private var day: Date?
    @State private var showBreakdown = false
    @State private var showReport = false
    @State private var showAlertEditor = false
    @State private var isNearSpot = false

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

    private var displayName: String {
        if let d = model.detail {
            return NameResolver.displayName(names: d.names, fallback: d.name, kind: d.kind, city: d.city)
        }
        return summary?.displayName ?? ""
    }

    var body: some View {
        List {
            headerSection
            scoreSection
            if isNearSpot {
                CrowdReportSection(spotID: spotID)
            }
            forecastSection
            amenitiesSection
            aboutSection
        }
        .groupedList()
        .navigationTitle(displayName)
        .inlineTitle()
        .toolbar {
            if let spot = currentSummary {
                ToolbarItem(placement: .primaryAction) { SaveButton(spot: spot) }
                if let url = mapsURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url, subject: Text(displayName))
                    }
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
            await model.load(id: spotID)
            app.track("spot_opened", ["kind": .string(model.detail?.kind ?? summary?.kind ?? "")])
            isNearSpot = await CrowdProximity.check(app: app, spot: coordinate,
                                                    kind: model.detail?.kind ?? summary?.kind ?? "")
        }
        .sheet(isPresented: $showBreakdown) {
            if let point = activePoint {
                ScoreBreakdownSheet(spotID: spotID, point: point, timeZone: timeZone)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(spotID: spotID)
        }
        .sheet(isPresented: $showAlertEditor) {
            AlertEditorSheet(spotID: spotID, spotName: displayName, timeZone: timeZone,
                             existing: app.alerts.rule(for: spotID))
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            if showsHeaderMap && !dynamicTypeSize.isAccessibilitySize, let coordinate = coordinate {
                HeaderMap(coordinate: coordinate, area: model.detail?.area)
                    .frame(height: 160)
                    .listRowInsets(EdgeInsets())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        Section {
            let score = activePoint?.score ?? summary?.score?.score
            let cap = activePoint?.capReason ?? summary?.score?.capReason
            let confidence = activePoint?.confidence ?? summary?.score?.confidence
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let score {
                            Text(score, format: .number)
                                .font(.system(.largeTitle, design: .rounded).bold())
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(score)))
                                .animation(.snappy(duration: 0.25), value: score)
                            Text(ScoreTier(score: score).label)
                                .font(.headline)
                                .foregroundStyle(ScoreTier(score: score).color)
                        } else {
                            Text("No forecast yet")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(scoreCaption(confidence: confidence))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: score, capReason: cap, diameter: 56)
                    .accessibilityHidden(true)
            }
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                Label(ReasonLocalizer.text(for: reason),
                      systemImage: ReasonLocalizer.symbol(for: reason.code) ?? "info.circle")
                    .symbolRenderingMode(.hierarchical)
            }
            if let score, activePoint != nil {
                Button("Why \(score)?") { showBreakdown = true }
            }
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let coordinate {
                Button {
                    Directions.open(name: displayName, coordinate: coordinate)
                    app.track("directions_opened")
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                showAlertEditor = true
            } label: {
                Label(app.alerts.rule(for: spotID) == nil ? "Alert" : "Edit Alert",
                      systemImage: app.alerts.rule(for: spotID) == nil ? "bell" : "bell.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                showReport = true
            } label: {
                Label("Report", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 4)
    }

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
                    Text("Drag across the chart to check another hour.")
                } else {
                    Text("Best score of each day. Hourly detail after tomorrow comes with Plus.")
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
            Button("Is this spot still here?") { showReport = true }
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

    /// Free plan: hourly detail for today and tomorrow; days 3+ need Plus (spec §15).
    private func dayNeedsPlus(_ index: Int) -> Bool {
        !app.isPlus && index >= 2
    }

    private func select(_ entry: WeekStrip.Day) {
        if entry.locked {
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
