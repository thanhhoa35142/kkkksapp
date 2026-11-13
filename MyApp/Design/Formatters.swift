import Foundation

/// Unit preferences (Settings → Units). `automatic` follows the device locale.
enum UnitPreference: String, CaseIterable, Identifiable {
    case automatic, metric, imperial
    var id: String { rawValue }

    static let temperatureKey = "units.temperature"
    static let distanceKey = "units.distance"

    static func current(_ key: String) -> UnitPreference {
        UnitPreference(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .automatic
    }
}

enum Format {
    /// "1.2 km" / "0.8 mi" — road usage picks m/km or ft/mi by locale.
    static func distance(meters: Double) -> String {
        let value = Measurement(value: meters, unit: UnitLength.meters)
        switch UnitPreference.current(UnitPreference.distanceKey) {
        case .automatic:
            return value.formatted(.measurement(width: .abbreviated, usage: .road))
        case .metric:
            let unit: UnitLength = meters < 1000 ? .meters : .kilometers
            return value.converted(to: unit).formatted(
                .measurement(width: .abbreviated, usage: .asProvided,
                             numberFormatStyle: .number.precision(.fractionLength(0...1))))
        case .imperial:
            let unit: UnitLength = meters < 300 ? .feet : .miles
            return value.converted(to: unit).formatted(
                .measurement(width: .abbreviated, usage: .asProvided,
                             numberFormatStyle: .number.precision(.fractionLength(0...1))))
        }
    }

    /// "21°" from a Celsius value; respects the temperature preference.
    static func temperature(celsius: Double) -> String {
        let value = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let style = Measurement<UnitTemperature>.FormatStyle(
            width: .narrow, usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0)))
        switch UnitPreference.current(UnitPreference.temperatureKey) {
        case .automatic:
            return value.formatted(.measurement(width: .narrow, usage: .weather,
                                                numberFormatStyle: .number.precision(.fractionLength(0))))
        case .metric:
            return style.format(value)
        case .imperial:
            return style.format(value.converted(to: .fahrenheit))
        }
    }

    /// "3 PM" in the given time zone.
    static func hour(_ date: Date, in timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "Today 3 PM", "Tomorrow 10 AM", "Sat 10 AM".
    static func dayHour(_ date: Date, in timeZone: TimeZone = .current, now: Date = .now) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let hour = hour(date, in: timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today \(hour)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow \(hour)")
        }
        var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
        weekday.timeZone = timeZone
        return "\(date.formatted(weekday)) \(hour)"
    }

    /// Short weekday ("Mon"), "Today" for the current day.
    static func dayLabel(_ date: Date, in timeZone: TimeZone, now: Date = .now) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
        weekday.timeZone = timeZone
        return date.formatted(weekday)
    }

    static func confidence(_ level: Int) -> String {
        switch level {
        case 3...: String(localized: "High confidence")
        case 2: String(localized: "Medium confidence")
        default: String(localized: "Low confidence")
        }
    }
}

extension Date {
    /// Truncated to the start of the hour (scores are hourly).
    var startOfHour: Date {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: self)
        return Calendar.current.date(from: comps) ?? self
    }
}
