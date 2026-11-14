import CoreLocation
import Foundation
import Observation

/// Loads "best spots around the current place at the selected hour"
/// (`GET /v1/recommendations`). Shared by the iPhone tab and the iPad/Mac sidebar.
@MainActor @Observable
final class BestNowModel {
    enum Phase: Equatable {
        case idle
        case needsPlace       // no place chosen / location denied
        case loading
        case loaded
        case empty            // no spots in range (outside covered cities)
        case filteredOut      // spots exist but none match the filters
        case dark             // every result is capped "dark" (after sunset)
        case failed(String)
    }

    private(set) var items: [SpotSummary] = []
    private(set) var phase: Phase = .idle
    private(set) var updatedAt: Date?
    /// "Better at 4 PM · 88" per spot — from real hourly scores, loaded after
    /// the rows so they render first. Missing = no line.
    private(set) var outlooks: [UUID: HourOutlook] = [:]
    /// True while a reload replaces rows that are already on screen: the list
    /// dims once and swaps its content in one step (UI_SPEC §8, one motion).
    private(set) var isRefreshing = false

    static let freeLimit = 3
    static let plusLimit = 30
    static let radiusM = 10_000.0

    /// Next 10:00 local — today if it's before 10, else tomorrow. Offered
    /// by the "It's dark out" state.
    nonisolated static func nextMorning(now: Date = .now, calendar: Calendar = .current) -> WhenSelection {
        let today10 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        let target = now < today10 ? today10 : (calendar.date(byAdding: .day, value: 1, to: today10) ?? today10)
        return .at(target)
    }

    /// True when the Free cap may be hiding more results.
    var mayHaveMore = false

    func load(app: AppState) async {
        guard app.place != nil else {
            phase = .needsPlace
            return
        }
        if items.isEmpty { phase = .loading } else { isRefreshing = true }
        defer { isRefreshing = false }
        guard let coordinate = await app.placeCoordinate() else {
            phase = .needsPlace
            return
        }
        let limit = app.isPlus ? Self.plusLimit : Self.freeLimit
        do {
            let list = try await AppConfig.apiClient.recommendations(
                lat: coordinate.latitude, lon: coordinate.longitude,
                radiusM: Self.radiusM, when: app.when.apiDate, limit: limit, filters: app.filters)
            items = list.items.map(SpotSummary.init)
            outlooks = [:]
            app.remember(items)
            mayHaveMore = !app.isPlus && items.count >= Self.freeLimit
            updatedAt = .now
            if items.isEmpty {
                phase = app.filters.isActive ? .filteredOut : .empty
            } else if items.allSatisfy({ $0.score?.capReason == "dark" }) {
                phase = .dark
            } else {
                phase = .loaded
            }
            // Keep the rows dimmed until their time lines arrive, so the
            // swap (rows + lines) happens in one step.
            await loadOutlooks(from: app.when.resolved, isPlus: app.isPlus)
        } catch is CancellationError {
            return
        } catch {
            // Keep stale rows visible when we have them (offline state).
            phase = items.isEmpty ? .failed(error.localizedDescription) : .loaded
            Log.api.error("recommendations failed: \(error.localizedDescription)")
        }
    }

    /// Hourly scores for the listed spots (one batch call), turned into the
    /// row's time line. Free: never past tomorrow (`HourWindow`).
    private func loadOutlooks(from: Date, isPlus: Bool) async {
        let hours = HourWindow.hours(from: from, isPlus: isPlus)
        let ids = items.map(\.id)
        guard hours >= 2, !ids.isEmpty else { return }
        do {
            let collection = try await AppConfig.apiClient.spots(ids: ids, from: from, hours: hours)
            var result: [UUID: HourOutlook] = [:]
            for feature in collection.features {
                let p = feature.properties
                guard let series = p.scores, let item = items.first(where: { $0.id == p.id }) else { continue }
                let outlook = HourOutlook.make(
                    hours: series.map { HourOutlook.Hour(tsHour: $0.tsHour, score: $0.score, capReason: $0.capReason) },
                    from: from, current: item.score?.score, timeZone: item.timeZone)
                if let outlook { result[p.id] = outlook }
            }
            outlooks = result
        } catch is CancellationError {
            return
        } catch {
            Log.api.error("best now hours failed: \(error.localizedDescription)")
        }
    }

    func outlookText(for spot: SpotSummary) -> String? {
        outlooks[spot.id]?.text(in: spot.timeZone)
    }
}
