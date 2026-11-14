import Foundation

/// How many hourly scores a list may ask for (`GET /v1/spots?ids=&from=&hours=`).
/// Free sees hour-by-hour today and tomorrow only (spec §15), so the window
/// stops at the start of the day after tomorrow — same rule as
/// `WhenSelection.needsPlus`. Pure — unit-tested.
enum HourWindow {
    static let maxHours = 12

    static func hours(from: Date, isPlus: Bool, maxHours: Int = maxHours,
                      now: Date = .now, calendar: Calendar = .current) -> Int {
        guard !isPlus else { return maxHours }
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: 2, to: today) else { return maxHours }
        let available = Int(cutoff.timeIntervalSince(from) / 3600)
        return max(0, min(maxHours, available))
    }
}

/// One line under a Best Now row that answers "which hour?":
/// "Better at 4 PM · 88", "Good until 6 PM", "No better hour later today".
/// Built only from real hourly scores. Pure — unit-tested.
enum HourOutlook: Equatable {
    /// A later hour today scores clearly higher.
    case betterAt(hour: Date, score: Int)
    /// Good now; drops under 60 at `end` (exclusive).
    case goodUntil(end: Date)
    /// Good for every hour we have data for; `last` is the last of them.
    case goodThrough(last: Date)
    /// Not good now, and no later hour today is better.
    case noBetterToday

    /// Points a later hour must beat the viewed hour by to be worth moving.
    static let minGain = 5
    static let goodScore = 60

    struct Hour: Equatable {
        let tsHour: Date
        let score: Int
        let capReason: String?
    }

    /// - Parameters:
    ///   - hours: hourly scores starting at (or before) `from`, any order.
    ///   - from: the hour being viewed (the row's score hour).
    ///   - current: the row's score at `from`.
    ///   - timeZone: the spot's zone — "later today" means the spot's day.
    static func make(hours: [Hour], from: Date, current: Int?, timeZone: TimeZone) -> HourOutlook? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sorted = hours.sorted { $0.tsHour < $1.tsHour }
        let start = from.addingTimeInterval(-60)
        // The rest of the spot's local day, starting at the viewed hour.
        let day = sorted.filter { $0.tsHour >= start && calendar.isDate($0.tsHour, inSameDayAs: from) }
        guard let first = day.first else { return nil }
        let now = current ?? first.score
        let later = day.dropFirst().filter { !isNight($0.capReason) }

        if let best = later.max(by: { a, b in a.score < b.score || (a.score == b.score && a.tsHour > b.tsHour) }),
           best.score >= now + minGain {
            return .betterAt(hour: best.tsHour, score: best.score)
        }
        if now >= goodScore {
            var last = first
            for hour in day.dropFirst() {
                if hour.score < goodScore || isNight(hour.capReason) {
                    return .goodUntil(end: hour.tsHour)
                }
                last = hour
            }
            return .goodThrough(last: last.tsHour)
        }
        return later.isEmpty ? nil : .noBetterToday
    }

    private static func isNight(_ cap: String?) -> Bool {
        cap == "dark" || cap == "twilight"
    }

    /// Display text in the spot's time zone.
    func text(in timeZone: TimeZone) -> String {
        switch self {
        case .betterAt(let hour, let score):
            String(localized: "Better at \(Format.hour(hour, in: timeZone)) · \(score)")
        case .goodUntil(let end):
            String(localized: "Good until \(Format.hour(end, in: timeZone))")
        case .goodThrough(let last):
            String(localized: "Good through \(Format.hour(last, in: timeZone))")
        case .noBetterToday:
            String(localized: "No better hour later today")
        }
    }

    /// Worth Meadow emphasis (a concrete good hour), vs. a neutral note.
    var isPositive: Bool {
        if case .noBetterToday = self { return false }
        return true
    }
}
