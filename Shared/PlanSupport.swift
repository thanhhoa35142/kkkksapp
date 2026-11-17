import Foundation

// Shared by the app and the widget: Foundation only.

// MARK: - Plan status

/// How a saved picnic plan looks now, from the latest hourly scores.
/// Pure — unit-tested.
enum PlanStatus: String, Codable, Sendable {
    /// Still a good window.
    case good
    /// Still usable, but clearly worse than when it was planned.
    case worse
    /// Rain / heat / cold cap in the window, or it no longer scores 60.
    case notRecommended

    /// Caps that make a window not worth going (bare `capReason` values).
    static let blockingCaps: Set<String> = ["rain", "heat", "cold"]
    /// Points the window's mean must drop (vs. when saved) to count as worse.
    static let worseDrop = 15

    /// nil when no hour of [start, end) is in `hours` (no data yet / past).
    static func classify(hours: [ScoredHour], start: Date, end: Date, scoreAtSave: Int) -> PlanStatus? {
        let window = hours.filter { $0.tsHour.timeIntervalSince(start) > -60 && $0.tsHour < end }
        guard !window.isEmpty else { return nil }
        if window.contains(where: { blockingCaps.contains($0.capReason ?? "") }) { return .notRecommended }
        let mean = Double(window.map(\.score).reduce(0, +)) / Double(window.count)
        if mean < Double(WeekPlanner.minScore) { return .notRecommended }
        if mean <= Double(scoreAtSave - worseDrop) { return .worse }
        return .good
    }
}

// MARK: - Links with an hour

/// `?at=<RFC 3339 UTC>` on spot links: "open this spot at this hour".
/// Built and checked here so the app, the widget and tests agree. Pure.
enum PlanLink {
    static let atKey = "at"
    static let sourceKey = "src"
    static let widgetSource = "widget"
    /// Links further out than this are ignored (the forecast is 7 days).
    static let maxDaysAhead = 7

    /// "2026-11-15T14:00:00Z" — UTC with `Z`, never an offset: a `+` in a
    /// query string turns into a space on many servers.
    static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Accepts `Z` or an offset, with or without fractional seconds.
    static func parse(_ raw: String) -> Date? {
        // A `+01:00` offset that went through form decoding arrives as " 01:00".
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "+")
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// Appends `at` (and optionally `src`) to a link.
    static func url(_ base: URL, at: Date?, source: String? = nil) -> URL {
        guard at != nil || source != nil,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var items = components.queryItems ?? []
        if let at { items.append(URLQueryItem(name: atKey, value: format(at))) }
        if let source { items.append(URLQueryItem(name: sourceKey, value: source)) }
        components.queryItems = items
        return components.url ?? base
    }

    /// The raw `at` hour of a link, unchecked.
    static func hour(in url: URL) -> Date? {
        value(of: atKey, in: url).flatMap(parse)
    }

    static func source(of url: URL) -> String? {
        value(of: sourceKey, in: url)
    }

    /// The hour to open, or nil to ignore it: floored to the hour, not in a
    /// past hour, less than `maxDaysAhead` out, and for Free before the
    /// start of the day after tomorrow (same rule as `HourWindow`).
    static func usableHour(_ date: Date, isPlus: Bool, now: Date = .now,
                           calendar: Calendar = .current) -> Date? {
        guard let hour = calendar.dateInterval(of: .hour, for: date)?.start,
              let nowHour = calendar.dateInterval(of: .hour, for: now)?.start,
              hour >= nowHour,
              hour < now.addingTimeInterval(TimeInterval(maxDaysAhead) * 86_400) else { return nil }
        if !isPlus {
            let today = calendar.startOfDay(for: now)
            guard let cutoff = calendar.date(byAdding: .day, value: 2, to: today), hour < cutoff else { return nil }
        }
        return hour
    }

    private static func value(of name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

// MARK: - Widget hand-off

/// A plan the app hands to the widget (App Group). Plain values only.
struct PlanSnapshot: Codable, Equatable, Sendable {
    var spotID: UUID
    var spotName: String
    var tz: String
    var start: Date
    var end: Date
    var scoreAtSave: Int
    /// The server's evaluation when forecast alerts are on for the plan (C2);
    /// nil otherwise and in data saved by older builds (decodes as nil).
    var serverStatus: PlanStatus? = nil

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }
}
