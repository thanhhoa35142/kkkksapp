import Foundation

/// The hour every screen is looking at ("Now", "Today 3 PM", "Sat 10 AM").
/// Shared across tabs via `AppState.when` (UI_SPEC §1).
enum WhenSelection: Equatable, Hashable {
    case now
    case at(Date) // start of an hour

    /// Hour sent to the API (`when=`); `nil` lets the server use "now".
    var apiDate: Date? {
        switch self {
        case .now: nil
        case .at(let date): date
        }
    }

    /// Concrete hour, for local lookups (forecast bars, time-lapse).
    var resolved: Date {
        switch self {
        case .now: Date.now.startOfHour
        case .at(let date): date
        }
    }

    var label: String {
        switch self {
        case .now: String(localized: "Now")
        case .at(let date): Format.dayHour(date)
        }
    }

    /// Free plan sees today and tomorrow hour by hour (spec §15); from the
    /// day after tomorrow it needs Plus. Same rule as Spot Detail's day picker.
    func needsPlus(now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: today) else { return false }
        return resolved >= dayAfterTomorrow
    }
}

/// Quick picks for the When menu.
enum WhenPreset: CaseIterable, Identifiable {
    case now, inTwoHours, thisEvening, tomorrowMorning, saturday, sunday
    var id: Self { self }

    var title: String {
        switch self {
        case .now: String(localized: "Now")
        case .inTwoHours: String(localized: "In 2 Hours")
        case .thisEvening: String(localized: "This Evening")
        case .tomorrowMorning: String(localized: "Tomorrow Morning")
        case .saturday: String(localized: "Saturday")
        case .sunday: String(localized: "Sunday")
        }
    }

    func selection(now: Date = .now, calendar: Calendar = .current) -> WhenSelection {
        func at(dayOffset: Int, hour: Int) -> WhenSelection {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
            let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? now
            return .at(date)
        }
        func next(weekday: Int, hour: Int) -> WhenSelection {
            let today = calendar.component(.weekday, from: now)
            var offset = (weekday - today + 7) % 7
            if offset == 0, calendar.component(.hour, from: now) >= hour { offset = 7 }
            return at(dayOffset: offset, hour: hour)
        }
        switch self {
        case .now:
            return .now
        case .inTwoHours:
            return .at(now.startOfHour.addingTimeInterval(2 * 3600))
        case .thisEvening:
            let evening = calendar.component(.hour, from: now) < 18 ? 0 : 1
            return at(dayOffset: evening, hour: 18)
        case .tomorrowMorning:
            return at(dayOffset: 1, hour: 10)
        case .saturday:
            return next(weekday: 7, hour: 12)
        case .sunday:
            return next(weekday: 1, hour: 12)
        }
    }
}
