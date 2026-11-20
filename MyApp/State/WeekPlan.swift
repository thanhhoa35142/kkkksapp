import Foundation
import Observation

// `PlanWindow` and `WeekPlanner` live in Shared/PicnicWindows.swift (the
// widget uses them too).

extension ForecastPoint: HourlyScored {}
extension HourOutlook.Hour: HourlyScored {}

/// S3 › This Week (Plus): the best window of each day across saved places.
/// One forecast call per place (7 × 24 h), first `maxSpots` in Saved order.
@MainActor @Observable
final class WeekPlanModel {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    static let maxSpots = 10

    private(set) var days: [PlanWindow] = []
    private(set) var phase: Phase = .idle

    func load(favorites: [FavoriteSpot]) async {
        let spots = Array(favorites.prefix(Self.maxSpots))
        guard !spots.isEmpty else { days = []; phase = .loaded; return }
        if days.isEmpty { phase = .loading }

        let inputs = spots.map { (id: $0.spotID, name: $0.name, tz: TimeZone(identifier: $0.tz) ?? .current) }
        var windows: [PlanWindow] = []
        var failures = 0
        await withTaskGroup(of: [PlanWindow]?.self) { group in
            for spot in inputs {
                group.addTask {
                    guard let points = try? await ForecastCache.shared.forecast(spotID: spot.id) else { return nil }
                    return WeekPlanner.bestPerDay(points, spotID: spot.id, spotName: spot.name, timeZone: spot.tz)
                }
            }
            for await result in group {
                if let result { windows += result } else { failures += 1 }
            }
        }
        if Task.isCancelled { return }
        if failures == inputs.count {
            phase = days.isEmpty ? .failed : .loaded
            return
        }
        days = Self.bestPerDay(windows)
        phase = .loaded
    }

    /// Across places: keep the top window of each day (day of the user's
    /// calendar — saved places are normally in one city).
    nonisolated static func bestPerDay(_ windows: [PlanWindow]) -> [PlanWindow] {
        let byDay = Dictionary(grouping: windows) { Calendar.current.startOfDay(for: $0.start) }
        return byDay.keys.sorted().compactMap { day in
            byDay[day]?.max { ($0.score, $0.hours) < ($1.score, $1.hours) }
        }
    }
}
