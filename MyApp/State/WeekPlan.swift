import Foundation
import Observation

/// One good picnic window: "Sat · 2–5 PM · Vondelpark · 88".
struct PlanWindow: Identifiable, Equatable, Sendable {
    let spotID: UUID
    let spotName: String
    let timeZone: TimeZone
    let start: Date
    /// Exclusive: the hour after the last good hour.
    let end: Date
    let score: Int

    var id: String { "\(spotID.uuidString)-\(start.timeIntervalSince1970)" }
    var hours: Int { Int(end.timeIntervalSince(start) / 3600) }
}

/// Finds windows in an hourly forecast. Pure — unit-tested.
enum WeekPlanner {
    static let minScore = 60
    static let minHours = 2
    static let maxHours = 4  // same cap as the backend digest (MaxWindowHours)
    /// Daylight picnic hours, spot-local: windows start ≥ 08:00, end ≤ 20:00.
    static let firstHour = 8
    static let lastHour = 20

    /// Best window per spot-local day (at most one per day), chronological.
    static func bestPerDay(_ points: [ForecastPoint], spotID: UUID, spotName: String,
                           timeZone: TimeZone, now: Date = .now) -> [PlanWindow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startHour = now.startOfHour
        let usable = points
            .filter { $0.tsHour >= startHour }
            .filter {
                let h = calendar.component(.hour, from: $0.tsHour)
                return h >= firstHour && h < lastHour
            }
            .sorted { $0.tsHour < $1.tsHour }
        let byDay = Dictionary(grouping: usable) { calendar.startOfDay(for: $0.tsHour) }

        return byDay.keys.sorted().compactMap { day in
            runs(in: byDay[day] ?? [])
                .compactMap { best(in: $0) }
                .max { $0.mean < $1.mean }
                .map { PlanWindow(spotID: spotID, spotName: spotName, timeZone: timeZone,
                                  start: $0.start, end: $0.end, score: Int($0.mean.rounded())) }
        }
    }

    /// Consecutive hours (1 h apart) that all score ≥ minScore.
    static func runs(in points: [ForecastPoint]) -> [[ForecastPoint]] {
        var result: [[ForecastPoint]] = []
        var current: [ForecastPoint] = []
        for point in points {
            if point.score >= minScore,
               current.last.map({ point.tsHour.timeIntervalSince($0.tsHour) == 3600 }) ?? true {
                current.append(point)
            } else {
                if current.count >= minHours { result.append(current) }
                current = point.score >= minScore ? [point] : []
            }
        }
        if current.count >= minHours { result.append(current) }
        return result
    }

    /// Peak 2-hour window inside a run, grown to neighbours that stay within
    /// 5 points of its mean (max 5 hours) — "2–5 PM", not "8 AM–8 PM".
    static func best(in run: [ForecastPoint]) -> (start: Date, end: Date, mean: Double)? {
        guard run.count >= minHours else { return nil }
        let scores = run.map { Double($0.score) }
        var lo = 0
        var bestMean = -1.0
        for i in 0...(run.count - minHours) {
            let mean = scores[i..<(i + minHours)].reduce(0, +) / Double(minHours)
            if mean > bestMean { bestMean = mean; lo = i }
        }
        var hi = lo + minHours  // exclusive
        let floor = bestMean - 5
        while hi - lo < maxHours {
            let left = lo > 0 ? scores[lo - 1] : -1
            let right = hi < run.count ? scores[hi] : -1
            if right >= floor, right >= left { hi += 1 }
            else if left >= floor { lo -= 1 }
            else { break }
        }
        let mean = scores[lo..<hi].reduce(0, +) / Double(hi - lo)
        return (run[lo].tsHour, run[hi - 1].tsHour.addingTimeInterval(3600), mean)
    }
}

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
                    guard let points = try? await AppConfig.apiClient.forecast(spotID: spot.id) else { return nil }
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
