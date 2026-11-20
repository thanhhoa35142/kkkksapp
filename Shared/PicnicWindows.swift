import Foundation

// Compiled into BOTH the app and the widget (Shared/ is a synchronized group
// of both targets): Foundation only — no app types (Format, SpotSummary, …).

/// Anything with an hourly score: the forecast points of Spot Detail, the
/// batch hours of Best Now, the widget's own decoded hours.
protocol HourlyScored {
    var tsHour: Date { get }
    var score: Int { get }
}

/// One hour of score with its cap ("rain", "dark", … — bare values, not the
/// `cap.*` reason codes).
struct ScoredHour: HourlyScored, Equatable, Sendable {
    let tsHour: Date
    let score: Int
    let capReason: String?
}

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
    static func bestPerDay<P: HourlyScored>(_ points: [P], spotID: UUID, spotName: String,
                                            timeZone: TimeZone, now: Date = .now) -> [PlanWindow] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
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
    static func runs<P: HourlyScored>(in points: [P]) -> [[P]] {
        var result: [[P]] = []
        var current: [P] = []
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
    /// 5 points of its mean (max `maxHours`) — "2–5 PM", not "8 AM–8 PM".
    static func best<P: HourlyScored>(in run: [P]) -> (start: Date, end: Date, mean: Double)? {
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

// MARK: - Decision (Best Now card, widget)

/// A spot the decision may pick, in the server's ranking order.
struct DecisionCandidate: Sendable {
    let spotID: UUID
    let spotName: String
    let timeZone: TimeZone
    /// Hourly scores from the selected hour on (any order).
    let hours: [ScoredHour]
}

/// "Today · Vondelpark · 4–6 PM": where and when to go. Pure — unit-tested.
struct PicnicDecision: Identifiable, Equatable, Sendable {
    let window: PlanWindow
    /// True when the window starts at the selected hour ("go now");
    /// false when the selected hour is unusable and this is the next good one.
    let startsAtSelectedHour: Bool

    var id: String { window.id }
}

enum DecisionPlanner {
    /// Reasons that hold for any hour of the spot. The rest (weather, crowd,
    /// caps) describe the selected hour only, so they are shown under a
    /// window only when it starts at that hour.
    static let timeIndependentReasonCodes: Set<String> = ["amenity.well_equipped", "fresh.recent"]

    /// 1. "Go now": the first candidate (ranking order) whose selected hour
    ///    starts a run of ≥ `WeekPlanner.minHours` good, uncapped hours —
    ///    the window runs from the selected hour, at most `maxHours` long.
    /// 2. Otherwise the next good window: the earliest spot-local day on
    ///    which any candidate has a `WeekPlanner` window (daylight, ≥ 60,
    ///    capped hours excluded); that day, the top-ranked candidate's
    ///    window if it has one, else the highest-scoring window.
    /// nil when no loaded hour gives a window (e.g. Free's hourly limit
    /// cuts the data short) — callers then show the plain top pick.
    static func decide(_ candidates: [DecisionCandidate], from: Date) -> PicnicDecision? {
        if let now = startingNow(candidates, from: from) {
            return PicnicDecision(window: now, startsAtSelectedHour: true)
        }
        return nextWindow(candidates, from: from).map { PicnicDecision(window: $0, startsAtSelectedHour: false) }
    }

    static func startingNow(_ candidates: [DecisionCandidate], from: Date) -> PlanWindow? {
        for candidate in candidates {
            let sorted = candidate.hours
                .filter { $0.tsHour.timeIntervalSince(from) > -60 }
                .sorted { $0.tsHour < $1.tsHour }
            guard let first = sorted.first, abs(first.tsHour.timeIntervalSince(from)) < 60 else { continue }
            var run: [ScoredHour] = []
            for hour in sorted {
                guard isGood(hour) else { break }
                if let last = run.last, hour.tsHour.timeIntervalSince(last.tsHour) != 3600 { break }
                run.append(hour)
                if run.count == WeekPlanner.maxHours { break }
            }
            guard run.count >= WeekPlanner.minHours, let last = run.last else { continue }
            let mean = Double(run.map(\.score).reduce(0, +)) / Double(run.count)
            return PlanWindow(spotID: candidate.spotID, spotName: candidate.spotName,
                              timeZone: candidate.timeZone, start: first.tsHour,
                              end: last.tsHour.addingTimeInterval(3600), score: Int(mean.rounded()))
        }
        return nil
    }

    static func nextWindow(_ candidates: [DecisionCandidate], from: Date) -> PlanWindow? {
        // (window, rank, local start of its day)
        var found: [(window: PlanWindow, rank: Int, day: Date)] = []
        for (rank, candidate) in candidates.enumerated() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = candidate.timeZone
            let uncapped = candidate.hours.filter { $0.capReason == nil }
            let windows = WeekPlanner.bestPerDay(uncapped, spotID: candidate.spotID, spotName: candidate.spotName,
                                                 timeZone: candidate.timeZone, now: from)
            for window in windows {
                found.append((window, rank, calendar.startOfDay(for: window.start)))
            }
        }
        guard let earliest = found.map(\.day).min() else { return nil }
        let thatDay = found.filter { $0.day == earliest }
        if let top = thatDay.first(where: { $0.rank == 0 }) { return top.window }
        return thatDay.max { a, b in
            a.window.score < b.window.score || (a.window.score == b.window.score && a.rank > b.rank)
        }?.window
    }

    private static func isGood(_ hour: ScoredHour) -> Bool {
        hour.score >= WeekPlanner.minScore && hour.capReason == nil
    }
}
