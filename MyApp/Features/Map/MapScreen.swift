import MapKit
import SwiftUI

/// S2 · Map tab (iPhone). Tapping a pin opens the spot in a sheet with
/// detents, like Apple Maps.
struct MapScreen: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            MapContainer(selection: sheetSelection)
                .navigationTitle("Map")
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { FilterButton() }
                    ToolbarItem(placement: .primaryAction) { WhenMenu() }
                }
        }
        .sheet(item: sheetItem) { ref in
            NavigationStack {
                SpotDetailView(spotID: ref.id, showsHeaderMap: false)
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
struct MapContainer: View {
    @Binding var selection: UUID?

    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = MapModel()
    @State private var search = LocalSearch()
    @State private var focus: MapFocus?

    var body: some View {
        SpotMapView(
            pins: model.pins,
            outlines: model.outlines,
            selection: selection,
            focus: focus,
            onSelect: { selection = $0 },
            onRegionChange: { model.regionChanged($0) },
            onUserPan: { model.pause() }
        )
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { statusOverlay }
        .overlay(alignment: .bottom) { timelapseBar }
        .overlay(alignment: .bottomLeading) {
            Text("© OpenStreetMap")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.bottom, 30)
                .allowsHitTesting(false)
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
        .onAppear { focusOnSelection() }
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

    /// M1 time-lapse: Play steps through 12 hours; Reduce Motion gets the
    /// slider only (no autoplay).
    @ViewBuilder
    private var timelapseBar: some View {
        if model.hoursAvailable > 1 && !model.tooWide {
            HStack(spacing: 12) {
                if !reduceMotion {
                    Button {
                        model.isPlaying ? model.pause() : model.play()
                        app.track("timelapse_play")
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 20)
                    }
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play hours")
                }
                Slider(
                    value: Binding(
                        get: { Double(model.hourOffset ?? 0) },
                        set: { model.pause(); model.hourOffset = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(model.hoursAvailable - 1, 1)),
                    step: 1
                )
                Text(timelapseLabel)
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 56, alignment: .trailing)
                if model.hourOffset != nil {
                    Button("Done") {
                        if let hour = model.timelapseHour { app.select(when: .at(hour)) }
                        model.resetTimelapse()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .sensoryFeedback(.selection, trigger: model.hourOffset)
        }
    }

    private var timelapseLabel: String {
        Format.hour(model.timelapseHour ?? app.when.resolved)
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
