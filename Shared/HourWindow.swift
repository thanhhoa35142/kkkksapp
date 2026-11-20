import Foundation

// Shared by the app and the widget: Foundation only.

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
