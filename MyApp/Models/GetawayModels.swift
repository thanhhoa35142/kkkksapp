import CoreLocation
import Foundation

// MARK: - Calendar day

/// A calendar date without a time or a time zone ("2026-11-21"). The server
/// sends `start`, `bestDay` and `dayScores[].date` this way, and the app does
/// its range maths on it: a `Date` would shift by a day across time zones.
/// Arithmetic runs on a fixed UTC Gregorian calendar, so it is the same on
/// every device and in unit tests.
struct CivilDay: Hashable, Comparable, Decodable {
    let year: Int
    let month: Int
    let day: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day `date` falls on in `timeZone`.
    init(_ date: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// "YYYY-MM-DD"; nil for anything else.
    init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = CivilDay(string: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD date: \(text)")
        }
        self = value
    }

    static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Midnight UTC of this day: the anchor for arithmetic and formatting.
    private var anchor: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// "2026-11-21", the query value for `start`.
    var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    func adding(days: Int) -> CivilDay {
        let moved = Self.utc.date(byAdding: .day, value: days, to: anchor) ?? anchor
        return CivilDay(moved, in: Self.utc.timeZone)
    }

    /// Whole days from `self` to `other` (negative when `other` is earlier).
    func days(until other: CivilDay) -> Int {
        Self.utc.dateComponents([.day], from: anchor, to: other.anchor).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday.
    var weekday: Int {
        Self.utc.component(.weekday, from: anchor)
    }

    /// Start of this day in `timeZone`, for a `DatePicker`.
    func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? anchor
    }

    /// "Sat" in the user's language.
    var weekdayLabel: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = Self.utc.timeZone
        return anchor.formatted(style)
    }

    /// "Sat, Nov 21" in the user's language.
    var mediumLabel: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = Self.utc.timeZone
        return anchor.formatted(style)
    }
}

// MARK: - Response

/// `GET /v1/getaways` (enveloped): cities ranked by picnic weather over a
/// date range. Order is the server's ranking.
struct GetawayList: Decodable {
    let start: CivilDay
    let days: Int
    let items: [Getaway]
    let computedAt: Date?
}

struct Getaway: Decodable, Identifiable {
    let slug: String
    let name: String
    let country: String
    let tz: String
    let center: [Double] // [lon, lat]
    let windowDays: Int
    let bestDay: CivilDay?
    let window: GetawayWindow
    let goodHours: Int
    let dayScores: [GetawayDayScore]
    let topSpot: GetawayTopSpot?
    let reasons: [Reason]

    var id: String { slug }

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    var coordinate: CLLocationCoordinate2D? {
        guard center.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: center[1], longitude: center[0])
    }

    /// Weather quality over the range: the best day's window. This is a
    /// WEATHER score, not a spot's total score; the total is `topSpot.score`.
    var weatherScore: Int { window.weatherScore }

    /// Reasons this build can phrase (newer server codes are skipped).
    var knownReasons: [Reason] {
        reasons.filter { ReasonLocalizer.isKnown($0.code) }
    }
}

/// The best window of the best day. `start` / `end` are UTC instants.
struct GetawayWindow: Decodable {
    let start: Date
    let end: Date
    let weatherScore: Int
}

/// One day of the range. `weatherScore` is nil for a day with no window. A
/// day that has already passed is not sent at all.
struct GetawayDayScore: Decodable {
    let date: CivilDay
    let weatherScore: Int?
    let goodHours: Int?
}

/// The city's best spot in the window. `score` is the spot's total score at
/// the window's best hour: the number `ScoreBadge` shows, so it matches the
/// spot after a tap.
struct GetawayTopSpot: Decodable {
    let id: String
    let name: String
    let score: Int?
}
