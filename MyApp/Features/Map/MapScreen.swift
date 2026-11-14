import Charts
import MapKit
import SwiftUI

/// S2 · Map tab (iPhone). Tapping a pin opens the spot in a sheet with
/// detents, like Apple Maps.
struct MapScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            // The spot sheet covers the bottom 220 pt: hide the time-lapse
            // bar while it is open instead of leaving it underneath.
            MapContainer(selection: sheetSelection, hidesTimelapseWhenSelected: true)
                .navigationTitle("Map")
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { FilterButton() }
                    ToolbarItem(placement: .primaryAction) { WhenMenu() }
                }
        }
        .sheet(item: sheetItem) { ref in
            NavigationStack {
                SpotDetailView(spotID: ref.id, context: .mapSheet)
            }
            .presentationDetents([.height(220), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .height(220)))
        }
    }

    /// The sheet belongs to this tab only, so Best Now pushes don't open it.
    private var sheetSelection: Binding<UUID?> {
        Binding(
            get: { app.selectedTab == .map ? app.selectedSpotID : nil },
            set: { app.selectedSpotID = $0 }
        )
    }

    private var sheetItem: Binding<SpotRef?> {
        Binding(
            get: { sheetSelection.wrappedValue.map(SpotRef.init) },
            set: { sheetSelection.wrappedValue = $0?.id }
        )
    }
}

struct SpotRef: Identifiable {
    let id: UUID
}

/// Map + overlays shared by the iPhone tab and the iPad/Mac Explore view.
///
/// Time-lapse rule (M1): scrubbing or playing *previews* an hour on the
/// pins; the app's "When" doesn't change. Opening a pin while previewing
/// commits that hour, so the spot shows the same hour as the pin that was
/// tapped. Changing "When" elsewhere ends the preview. Dragging back to the
/// start shows "When" again.
struct MapContainer: View {
    @Binding var selection: UUID?
    /// iPhone: the spot sheet sits over the bottom of the map.
    var hidesTimelapseWhenSelected = false

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = MapModel()
    @State private var search = LocalSearch()
    @State private var focus: MapFocus?
    @State private var isScrubbing = false

    var body: some View {
        SpotMapView(
            pins: model.pins,
            outlines: model.outlines,
            selection: selection,
            focus: focus,
            onSelect: select,
            onRegionChange: { model.regionChanged($0) },
            onUserPan: { model.pause() }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statusOverlay }
        .overlay(alignment: .bottom) {
            VStack(spacing: 6) {
                if showsTimelapse {
                    timelapseBar
                }
                // Centered: Apple's own "Legal" sits bottom-left (iOS) and the
                // zoom controls bottom-right (Mac), so the middle stays free.
                Text(verbatim: "© OpenStreetMap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            .padding(.bottom, 6)
        }
        .searchable(text: $search.query, prompt: "Search places")
        .searchSuggestions {
            ForEach(search.results) { result in
                Button {
                    Task { await go(to: result) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(result.title)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task(id: LoadKey(region: model.regionVersion, when: app.when, filters: app.filters)) {
            // Debounce: load once the map stops moving.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await model.load(when: app.when, app: app)
        }
        .task(id: app.place) { await focusOnPlace() }
        .onChange(of: app.mapFocusVersion) { _, _ in focusOnSelection() }
        .onChange(of: app.when) { _, _ in model.resetTimelapse() }
        .onChange(of: search.query) { _, _ in search.update() }
        .onChange(of: reduceMotion) { _, on in if on { model.pause() } }
        .onAppear { focusOnSelection() }
    }

    private var showsTimelapse: Bool {
        model.hoursAvailable > 1 && !model.tooWide && !(hidesTimelapseWhenSelected && selection != nil)
    }

    /// Opening a pin while previewing an hour makes that hour the "When".
    private func select(_ id: UUID?) {
        if id != nil, let hour = model.previewHour {
            model.pause()
            app.select(when: hour <= Date.now.startOfHour ? .now : .at(hour))
            app.track("timelapse_committed")
        }
        selection = id
    }

    // MARK: Overlays

    @ViewBuilder
    private var statusOverlay: some View {
        if model.tooWide {
            Text("Zoom in to see spots")
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        } else if model.isLoading && model.features.isEmpty {
            ProgressView()
                .padding(10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
        }
    }

    /// M1 time-lapse: the hour label is the anchor; a flat sparkline of the
    /// visible spots' average score sits over the scrubber, so dragging shows
    /// where the day peaks. Play steps through the hours; Reduce Motion gets
    /// the scrubber only (no autoplay). Haptics only while the user drags.
    private var timelapseBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(timelapseLabel)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(.smooth(duration: 0.2), value: model.hourOffset)
                if model.previewHour != nil {
                    Text("Preview")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !reduceMotion {
                    Button {
                        model.isPlaying ? model.pause() : model.play()
                        app.track("timelapse_play")
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 20)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play hours")
                }
            }
            HourSparkline(values: model.hourlyAverages, selected: model.hourOffset ?? 0)
                .frame(height: 22)
                .padding(.horizontal, 10)
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(model.hourOffset ?? 0) },
                    set: { model.pause(); model.hourOffset = Int($0.rounded()) }
                ),
                in: 0...Double(max(model.hoursAvailable - 1, 1)),
                step: 1,
                onEditingChanged: { isScrubbing = $0 }
            )
            .accessibilityLabel(Text("Hour"))
            .accessibilityValue(Text(timelapseLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .frame(maxWidth: 520)
        .sensoryFeedback(.selection, trigger: model.hourOffset) { _, _ in isScrubbing }
    }

    private var timelapseLabel: String {
        guard let hour = model.previewHour else { return app.when.label }
        return Format.dayHour(hour)
    }

    // MARK: Camera

    private func focusOnPlace() async {
        guard let coordinate = await app.placeCoordinate() else { return }
        focus = MapFocus(version: (focus?.version ?? 0) + 1,
                         latitude: coordinate.latitude, longitude: coordinate.longitude, span: 0.06)
    }

    private func focusOnSelection() {
        guard let id = selection ?? app.selectedSpotID,
              let coordinate = app.summaries[id]?.coordinate else { return }
        focus = MapFocus(version: (focus?.version ?? 0) + 1,
                         latitude: coordinate.latitude, longitude: coordinate.longitude, span: 0.02)
    }

    private func go(to result: LocalSearch.Result) async {
        guard let coordinate = await search.resolve(result) else { return }
        focus = MapFocus(version: (focus?.version ?? 0) + 1,
                         latitude: coordinate.latitude, longitude: coordinate.longitude, span: 0.05)
        search.query = ""
    }

    private struct LoadKey: Equatable {
        let region: Int
        let when: WhenSelection
        let filters: SpotFilters
    }
}

/// Flat bars: average score per hour of the visible spots. The scrubbed hour
/// is Meadow, the rest neutral. Decorative twin of the slider below it.
private struct HourSparkline: View {
    let values: [Int?]
    let selected: Int

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("Hour", Double(index)),
                    y: .value("Average", value ?? 0),
                    width: .ratio(0.7)
                )
                .foregroundStyle(index == selected ? Color.brand : Color.secondary.opacity(0.35))
                .cornerRadius(1.5)
            }
        }
        .chartXScale(domain: -0.5...(Double(max(values.count, 1)) - 0.5))
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
