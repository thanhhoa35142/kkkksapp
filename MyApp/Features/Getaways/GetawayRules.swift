import CoreLocation
import Foundation

/// Where the Getaways sheet was opened from (`getaways_opened.source`).
enum GetawaySource: String, Identifiable {
    case placeMenu, hint
    var id: Self { self }
}

/// The ranges the toolbar menu offers. `custom` is "Pick Days…".
enum GetawayPreset: String, CaseIterable, Identifiable {
    case thisWeekend, nextWeekend, today, tomorrow, custom
    var id: Self { self }

    /// The presets listed in the menu above "Pick Days…".
    static let menuPresets: [GetawayPreset] = [.thisWeekend, .nextWeekend, .today, .tomorrow]

    var title: String {
        switch self {
        case .thisWeekend: String(localized: "This Weekend")
        case .nextWeekend: String(localized: "Next Weekend")
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .custom: String(localized: "Pick Days…")
        }
    }
}

/// `days` calendar days from `start` (1...3).
struct GetawayRange: Equatable {
    var start: CivilDay
    var days: Int

    var end: CivilDay { start.adding(days: days - 1) }
}

/// Pure rules for Getaways: ranges, the hint, distance. No UI, no state, so
/// they can be unit-tested with a fixed `now` and time zone.
enum GetawayRules {
    /// Free sees 3 cities (the server clamps `limit` the same way).
    static let freeLimit = 3
    /// Server maximum for `limit`.
    static let plusLimit = 39
    /// Rows in the city picker's "Great This Weekend" section.
    static let sectionCount = 3
    static let maxRangeDays = 3
    /// The server forecasts 7 local days: today ... today + 6.
    static let horizonDays = 6
    /// Within this distance a city counts as "near" (1,500 km).
    static let nearMeters: Double = 1_500_000
    /// A weekend window at or above this score is already good at home.
    static let comfortableScore = 65
    /// The hint needs a city at or above this score (`HINT_MIN`).
    static let hintMinScore = 80
    static let hintShownKey = "getawaysHintShownAt"

    static func limit(isPlus: Bool) -> Int {
        isPlus ? plusLimit : freeLimit
    }

    // MARK: Dates

    private static var utc: TimeZone { TimeZone(identifier: "UTC") ?? .gmt }

    static func currentDay(now: Date = .now, timeZone: TimeZone = .current) -> CivilDay {
        CivilDay(now, in: timeZone)
    }

    /// Last day the server accepts. It checks against the UTC date, so a
    /// device ahead of UTC must not count its own "today" (400 `invalid_range`).
    static func lastDay(now: Date = .now, timeZone: TimeZone = .current) -> CivilDay {
        min(currentDay(now: now, timeZone: timeZone), currentDay(now: now, timeZone: utc)).adding(days: horizonDays)
    }

    /// The range for a preset, or nil when its forecast is not out yet
    /// (or for `custom`). Ranges that run past the horizon lose their tail.
    static func range(for preset: GetawayPreset, now: Date = .now, timeZone: TimeZone = .current) -> GetawayRange? {
        let today = currentDay(now: now, timeZone: timeZone)
        let weekday = today.weekday // 1 = Sunday ... 7 = Saturday
        // Coming Saturday, or today on Saturday and Sunday.
        let saturday = today.adding(days: weekday == 1 ? 0 : 7 - weekday)
        let start: CivilDay
        let days: Int
        switch preset {
        case .today:
            start = today
            days = 1
        case .tomorrow:
            start = today.adding(days: 1)
            days = 1
        case .thisWeekend:
            start = saturday
            // On Sunday only Sunday is left; 2 days would add Monday.
            days = weekday == 1 ? 1 : 2
        case .nextWeekend:
            // The Saturday after this weekend: 6 days out on Sunday, else 7 after this one.
            start = weekday == 1 ? today.adding(days: 6) : saturday.adding(days: 7)
            days = 2
        case .custom:
            return nil
        }
        let last = lastDay(now: now, timeZone: timeZone)
        guard start <= last else { return nil }
        return GetawayRange(start: start, days: min(days, start.days(until: last) + 1))
    }

    static func isAvailable(_ preset: GetawayPreset, now: Date = .now, timeZone: TimeZone = .current) -> Bool {
        preset == .custom || range(for: preset, now: now, timeZone: timeZone) != nil
    }

    /// First days "Pick Days…" can start on: today ... today + 5.
    static func pickableStarts(now: Date = .now, timeZone: TimeZone = .current) -> ClosedRange<CivilDay> {
        let today = currentDay(now: now, timeZone: timeZone)
        let latest = min(today.adding(days: 5), lastDay(now: now, timeZone: timeZone))
        return today...max(today, latest)
    }

    /// 1...3, and the range must end by the horizon.
    static func maxDays(from start: CivilDay, now: Date = .now, timeZone: TimeZone = .current) -> Int {
        let room = start.days(until: lastDay(now: now, timeZone: timeZone)) + 1
        return max(1, min(maxRangeDays, room))
    }

    /// Pulls a hand-picked range back into what the server accepts.
    static func clamped(_ range: GetawayRange, now: Date = .now, timeZone: TimeZone = .current) -> GetawayRange {
        let starts = pickableStarts(now: now, timeZone: timeZone)
        let start = min(max(range.start, starts.lowerBound), starts.upperBound)
        return GetawayRange(start: start,
                            days: min(max(range.days, 1), maxDays(from: start, now: now, timeZone: timeZone)))
    }

    /// "Forecasts more than 3 days out can change." applies from here on.
    static func showsUncertaintyFooter(_ range: GetawayRange, now: Date = .now, timeZone: TimeZone = .current) -> Bool {
        range.start > currentDay(now: now, timeZone: timeZone).adding(days: 2)
    }

    // MARK: Distance

    static func distanceMeters(from origin: CLLocationCoordinate2D?, to city: Getaway) -> Double? {
        guard let origin, let target = city.coordinate else { return nil }
        return origin.distanceMeters(to: target)
    }

    /// `near` within 1,500 km, else `far`; `unknown` when there is no fix.
    static func distanceBucket(meters: Double?) -> String {
        guard let meters else { return "unknown" }
        return meters <= nearMeters ? "near" : "far"
    }

    static func nearCount(_ items: [Getaway], from origin: CLLocationCoordinate2D?) -> Int {
        items.filter { (distanceMeters(from: origin, to: $0) ?? .infinity) <= nearMeters }.count
    }

    // MARK: Home city

    /// The user's city: the chosen city's slug, or the pack that contains the
    /// last location fix. nil when unknown.
    static func homeSlug(place: Place?, packs: [CityPack], fix: CLLocationCoordinate2D?) -> String? {
        guard let place else { return nil }
        switch place {
        case .city(let slug, _, _, _):
            return slug
        case .currentLocation:
            guard let fix else { return nil }
            return packs.first { pack in
                guard pack.bbox.count >= 4 else { return false }
                return fix.longitude >= pack.bbox[0] && fix.longitude <= pack.bbox[2]
                    && fix.latitude >= pack.bbox[1] && fix.latitude <= pack.bbox[3]
            }?.slug
        }
    }

    /// Where distances are measured from: the last fix, else the chosen city.
    static func origin(place: Place?, fix: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        if let fix { return fix }
        if case .city(_, _, let latitude, let longitude)? = place {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        return nil
    }

    // MARK: Hint

    /// The city for "This weekend looks better in Lisbon", or nil. All four
    /// must hold: (a) the user's city has no window >= 65 this weekend,
    /// (b) another city scores >= 80, (c) it is within 1,500 km, and (d) the
    /// hint was not shown this week.
    ///
    /// `items` is the weekend response asked with `requestedLimit`. The server
    /// omits cities without a window, but Free only gets the top 3: a city
    /// missing from a full list may still be good, so (a) then stays unknown
    /// and nothing is shown.
    static func hintCity(items: [Getaway], requestedLimit: Int, homeSlug: String?,
                         origin: CLLocationCoordinate2D?, shownThisWeek: Bool) -> Getaway? {
        guard !shownThisWeek, let homeSlug, let origin else { return nil }
        if let home = items.first(where: { $0.slug == homeSlug }) {
            if hasComfortableWeekend(home) { return nil }
        } else if items.count >= requestedLimit {
            return nil
        }
        return items.first { city in
            city.slug != homeSlug
                && city.weatherScore >= hintMinScore
                && (distanceMeters(from: origin, to: city) ?? .infinity) <= nearMeters
        }
    }

    static func hasComfortableWeekend(_ city: Getaway) -> Bool {
        city.weatherScore >= comfortableScore || city.dayScores.contains { ($0.weatherScore ?? 0) >= comfortableScore }
    }

    /// Once a week: the week of the last time the hint appeared.
    static func hintShownThisWeek(defaults: UserDefaults = .standard, now: Date = .now,
                                  calendar: Calendar = .current) -> Bool {
        guard let last = defaults.object(forKey: hintShownKey) as? Date else { return false }
        return calendar.isDate(last, equalTo: now, toGranularity: .weekOfYear)
    }

    static func markHintShown(defaults: UserDefaults = .standard, now: Date = .now) {
        defaults.set(now, forKey: hintShownKey)
    }

    // MARK: Opening a city

    /// The place to switch to. The pack (from `/v1/packs`) wins when it is
    /// loaded; the item's own `center` covers the sheet opening before packs.
    static func place(for city: Getaway, pack: CityPack?) -> Place? {
        guard let coordinate = pack?.coordinate ?? city.coordinate else { return nil }
        return .city(slug: city.slug, name: pack?.name ?? city.name,
                     latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The hour to show Best Now at after opening a city: its window start,
    /// or now when that hour has begun already (the server counts from now).
    static func selection(for city: Getaway, now: Date = .now) -> WhenSelection {
        city.window.start <= now.startOfHour ? .now : .at(city.window.start)
    }

    // MARK: Row text

    /// Regional-indicator flag for an ISO 3166 code; "" for anything else.
    static func flag(for countryCode: String) -> String {
        let code = countryCode.uppercased()
        guard code.unicodeScalars.count == 2 else { return "" }
        var flag = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard (65...90).contains(scalar.value),
                  let regional = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return "" }
            flag.append(regional)
        }
        return String(flag)
    }

    /// "Sun 1 PM–5 PM" in the city's time zone.
    static func windowLabel(_ city: Getaway) -> String {
        var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
        weekday.timeZone = city.timeZone
        let day = city.window.start.formatted(weekday)
        let from = Format.hour(city.window.start, in: city.timeZone)
        let to = Format.hour(city.window.end, in: city.timeZone)
        return "\(day) \(from)–\(to)"
    }

    /// True when the window's clock time differs from the device's, so the
    /// row says it is the city's local time.
    static func showsLocalTimeCaption(_ city: Getaway, deviceTimeZone: TimeZone = .current) -> Bool {
        let instant = city.window.start
        return city.timeZone.secondsFromGMT(for: instant) != deviceTimeZone.secondsFromGMT(for: instant)
    }

    /// "Sat 71 · Sun 86" (weather scores). A day without a good window is
    /// left out rather than shown as "–", which read as missing data.
    /// nil for a single day or no scored day; the row then shows the
    /// city's weather score alone.
    static func dayScoresLine(_ city: Getaway) -> String? {
        guard city.dayScores.count > 1 else { return nil }
        let parts = city.dayScores.compactMap { entry in
            entry.weatherScore.map { "\(entry.date.weekdayLabel) \($0)" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
