import Foundation
import MapKit
import Observation

/// One pin on the map — value type handed to the MKMapView wrapper.
struct MapPin: Equatable {
    let id: UUID
    let title: String
    let latitude: Double
    let longitude: Double
    let score: Int?
    let capReason: String?
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// Viewport loading + time-lapse (UI_SPEC S2, §8.1 M1).
@MainActor @Observable
final class MapModel {
    /// API limit: each bbox axis ≤ 0.5°.
    static let maxSpan = 0.45
    /// Below this span, ask for park outlines.
    static let outlineSpan = 0.05
    static let timelapseHours = 12

    private(set) var features: [SpotFeature] = []
    private(set) var isLoading = false
    private(set) var tooWide = false
    private(set) var loadedFrom: Date?
    private(set) var error: String?

    /// Region reported by the map; bumping `regionVersion` triggers a
    /// debounced load in the view.
    private(set) var region: MKCoordinateRegion?
    private(set) var regionVersion = 0

    // Time-lapse
    var hourOffset: Int?
    private(set) var isPlaying = false
    private var playTask: Task<Void, Never>?

    var hoursAvailable: Int {
        features.map { $0.properties.scores?.count ?? 0 }.max() ?? 0
    }

    var timelapseHour: Date? {
        guard let hourOffset, let loadedFrom else { return nil }
        return loadedFrom.addingTimeInterval(Double(hourOffset) * 3600)
    }

    func regionChanged(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        regionVersion += 1
    }

    var pins: [MapPin] {
        let hour = timelapseHour
        return features.compactMap { feature in
            guard let c = feature.geometry.coordinate else { return nil }
            let p = feature.properties
            var score = p.score?.score
            var cap = p.score?.capReason
            if let hour {
                let match = p.scores?.first { abs($0.tsHour.timeIntervalSince(hour)) < 60 }
                score = match?.score
                cap = match?.capReason
            }
            return MapPin(id: p.id, title: SpotSummary(feature).displayName,
                          latitude: c.latitude, longitude: c.longitude,
                          score: score, capReason: cap)
        }
    }

    /// Outlines for zoomed-in viewports, keyed by spot id.
    var outlines: [UUID: JSONValue] {
        var result: [UUID: JSONValue] = [:]
        for f in features {
            if let area = f.properties.area { result[f.properties.id] = area }
        }
        return result
    }

    func load(when: WhenSelection, app: AppState) async {
        guard let region else { return }
        let span = max(region.span.latitudeDelta, region.span.longitudeDelta)
        tooWide = span > Self.maxSpan
        guard !tooWide else { return }
        isLoading = true
        defer { isLoading = false }
        let from = when.resolved
        do {
            let collection = try await AppConfig.apiClient.spots(
                bbox: GeoMath.bbox(for: region, padding: 0.01),
                when: when.apiDate,
                from: from,
                hours: Self.timelapseHours,
                includeArea: span < Self.outlineSpan,
                filters: app.filters)
            features = collection.features
            loadedFrom = from
            error = nil
            app.remember(collection.features.map(SpotSummary.init))
            if let offset = hourOffset, offset >= hoursAvailable { hourOffset = nil }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
            Log.api.error("map spots failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Time-lapse

    /// Steps through the loaded hours, ~0.6 s each; user-initiated only.
    func play() {
        guard hoursAvailable > 1 else { return }
        pause()
        if (hourOffset ?? 0) >= hoursAvailable - 1 { hourOffset = 0 }
        if hourOffset == nil { hourOffset = 0 }
        isPlaying = true
        playTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                let next = (self.hourOffset ?? 0) + 1
                if next >= self.hoursAvailable {
                    self.isPlaying = false
                    return
                }
                self.hourOffset = next
            }
        }
    }

    func pause() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    /// Ends the time-lapse and goes back to the selected hour.
    func resetTimelapse() {
        pause()
        hourOffset = nil
    }
}
