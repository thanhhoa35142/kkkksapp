import Foundation
import SwiftData
import SwiftUI

/// UI-test mode: launch with `-UITestFixtures` and every API call is answered
/// from the canned data below, so layout tests run on CI without a backend.
/// Debug builds only — Release compiles this to "never active".
///
/// Extra launch arguments:
/// - `-UITestPlan plus` → Plus entitlement (default Free)
/// - `-onboardingDone YES` → skip onboarding (plain UserDefaults argument)
/// - `-UIPreferredContentSizeCategoryName <category>` → Dynamic Type
/// - `-UITestLocalHour <0–23>` → the fixture city's local hour at launch (default 10)
/// - `-UITestAppearance dark|light` → color scheme for screenshots (default: system)
/// - `-UITestDelay <seconds>` → every response waits this long (loading states)
/// - `-UITestOffline YES` → every request fails as "not connected to the internet"
///
/// Names are deliberately long/awkward to catch wrapping and truncation.
enum UITestFixtures {
    typealias JSON = [String: Any]

    #if DEBUG
    static let isActive = ProcessInfo.processInfo.arguments.contains("-UITestFixtures")
    #else
    static let isActive = false
    #endif

    /// `-UITestAppearance`: a fixed color scheme for screenshot runs. nil =
    /// follow the system (always, outside fixture mode).
    static var colorScheme: ColorScheme? {
        guard isActive else { return nil }
        switch UserDefaults.standard.string(forKey: "UITestAppearance") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// `-UITestDelay`: seconds before each response (0 = immediate).
    static var responseDelay: TimeInterval {
        UserDefaults.standard.double(forKey: "UITestDelay")
    }

    /// `-UITestOffline YES`: requests fail the way they do without a network.
    static var isOffline: Bool {
        UserDefaults.standard.bool(forKey: "UITestOffline")
    }

    static var isPlus: Bool {
        UserDefaults.standard.string(forKey: "UITestPlan") == "plus"
    }

    /// URLSession whose requests never leave the process.
    static var session: URLSession? {
        guard isActive else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureURLProtocol.self]
        return URLSession(configuration: config)
    }

    static let place = Place.city(slug: "amsterdam", name: "Amsterdam", latitude: 52.37, longitude: 4.89)

    /// The fixture city's clock. Scores follow the spot-local daylight curve
    /// (dark before 08:00 and from 20:00), so with the real Amsterdam zone a
    /// CI run at night saw only "It's dark out" and every Best Now layout
    /// check failed. Instead the city gets the fixed-offset zone in which it
    /// is `localHour` o'clock at launch (default 10 = mid-morning), so the
    /// screens look the same whenever CI runs. `-UITestLocalHour 2` tests the
    /// night state on purpose.
    static let localHour: Int = {
        let raw = UserDefaults.standard.object(forKey: "UITestLocalHour") as? String
        return raw.flatMap(Int.init).map { min(max($0, 0), 23) } ?? 10
    }()

    static let timeZone: TimeZone = {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var offset = localHour - utc.component(.hour, from: .now)  // hours ahead of UTC
        if offset < -12 { offset += 24 }   // IANA fixed zones span UTC−12…UTC+14
        if offset > 14 { offset -= 24 }
        // POSIX sign: "Etc/GMT-10" is UTC+10.
        let id = offset == 0 ? "Etc/GMT" : "Etc/GMT\(offset > 0 ? "-" : "+")\(abs(offset))"
        return TimeZone(identifier: id) ?? TimeZone(secondsFromGMT: offset * 3600)!
    }()

    static var timeZoneID: String { timeZone.identifier }

    // MARK: Spots

    struct Spot {
        let id: UUID
        let kind: String
        let name: String
        let lon: Double
        let lat: Double
        let distanceM: Double
        let base: Int
        let cap: String?
    }

    static let spots: [Spot] = [
        Spot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, kind: "park",
             name: "Vondelpark", lon: 4.8686, lat: 52.3580, distanceM: 1200, base: 86, cap: nil),
        Spot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, kind: "park",
             name: "Koningin Wilhelminapark en Speeltuin De Bolderik aan de Amstel",
             lon: 4.9002, lat: 52.3401, distanceM: 3400, base: 74, cap: nil),
        Spot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, kind: "site",
             name: "Picknickplaats Amsterdamse Bos – Grote Vijver Noordoever",
             lon: 4.8450, lat: 52.3300, distanceM: 6800, base: 58, cap: "rain"),
        Spot(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, kind: "beach",
             name: "Blijburg", lon: 5.0010, lat: 52.3590, distanceM: 9100, base: 41, cap: nil),
    ]

    static func spot(_ id: UUID) -> Spot? { spots.first { $0.id == id } }

    /// Hourly score: daylight curve per day, capped "dark" at night.
    static func score(_ spot: Spot, at date: Date) -> (score: Int, cap: String?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        let day = calendar.component(.weekday, from: date)
        guard (8..<20).contains(hour) else { return (10, "dark") }
        let curve = sin(Double(hour - 8) / 12 * .pi)       // 0 → 1 → 0
        let wobble = Double((day * 7) % 11) - 5             // per-day variation
        let value = Double(spot.base) - 18 + curve * 22 + wobble
        return (max(5, min(98, Int(value.rounded()))), spot.cap)
    }

    // MARK: Favorites

    /// In-memory store with three saved spots (Saved, This Week).
    static func makeModelContainer() -> ModelContainer? {
        guard isActive else { return nil }
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: FavoriteSpot.self, PicnicPlan.self, configurations: config) else { return nil }
        let context = ModelContext(container)
        for (index, spot) in spots.prefix(3).enumerated() {
            let summary = SpotSummary(id: spot.id, kind: spot.kind, name: spot.name, names: [:], city: "Amsterdam",
                                      tz: timeZoneID, latitude: spot.lat, longitude: spot.lon,
                                      distanceM: spot.distanceM, score: nil)
            context.insert(FavoriteSpot(summary: summary, sortIndex: index))
        }
        try? context.save()
        return container
    }

    // MARK: Responses

    static func response(for request: URLRequest) -> (Int, Data) {
        guard let url = request.url else { return problem(400, "invalid_url") }
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let method = request.httpMethod ?? "GET"
        let parts = path.split(separator: "/").map(String.init)  // ["v1", ...]

        switch (method, parts.count > 1 ? parts[1] : "") {
        case ("POST", "devices"):
            return ok(["id": UUID().uuidString])
        case ("GET", "devices") where parts.last == "entitlement":
            let plus: [String: Any] = ["plan": "plus", "productId": "com.pickhour.plus.yearly",
                                       "expiresAt": iso(.now.addingTimeInterval(300 * 86_400)), "autoRenew": true]
            let free: [String: Any] = ["plan": "free"]
            return ok(isPlus ? plus : free)
        case (_, "devices") where parts.last == "digest":
            guard isPlus else { return problem(404, "not_found") }
            return ok(["spotIds": spots.prefix(3).map(\.id.uuidString), "enabled": true,
                       "sendDow": 4, "sendHour": 18, "skippedIds": [String]()] as JSON)
        case (_, "devices") where parts.last == "nudge":
            // Good-day push: DELETE is 204; GET / PUT answer an active subscription.
            if method == "DELETE" { return (204, Data()) }
            return ok(["enabled": true, "sendHour": 8, "homeSet": true, "homeUpdatedAt": iso(.now)] as JSON)
        case ("GET", "alerts"):
            return ok(["items": [alertRule()]])
        case ("POST", "events"):
            return ok(["status": "accepted", "count": 1] as JSON)
        case ("POST", _):
            return ok(["status": "accepted"])
        case ("GET", "packs"):
            return ok(["items": [JSON]([[
                "slug": "amsterdam", "name": "Amsterdam", "country": "NL", "tz": timeZoneID,
                "center": [4.89, 52.37], "bbox": [4.73, 52.28, 5.07, 52.43], "activeSpots": 412,
            ]])])
        case ("GET", "getaways"):
            return ok(getaways(start: q("start"), days: Int(q("days") ?? "") ?? 2))
        case ("GET", "recommendations"):
            let when = q("when").flatMap(parseISO) ?? .now
            let limit = Int(q("limit") ?? "") ?? 3
            return ok(["when": iso(when), "items": spots.prefix(limit).map { recommendation($0, at: when) }] as JSON)
        case ("GET", "weather"):
            let start = Date.now.startOfHour
            return ok((0..<24).map { nearbyWeatherPoint(at: start.addingTimeInterval(Double($0) * 3600), index: $0) })
        case ("GET", "spots") where parts.count == 2:
            let when = q("when").flatMap(parseISO) ?? .now
            let from = q("from").flatMap(parseISO)
            let hours = Int(q("hours") ?? "")
            var chosen = spots
            if let ids = q("ids") {
                let wanted = Set(ids.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
                chosen = spots.filter { wanted.contains($0.id) }
            }
            return raw(["type": "FeatureCollection",
                        "features": chosen.map { feature($0, at: when, from: from, hours: hours) }] as JSON)
        case ("GET", "spots") where parts.count == 3:
            guard let id = UUID(uuidString: parts[2]), let spot = spot(id) else { return problem(404, "not_found") }
            return ok(detail(spot))
        case ("GET", "spots") where parts.last == "forecast":
            guard let id = UUID(uuidString: parts[2]), let spot = spot(id) else { return problem(404, "not_found") }
            let start = Date.now.startOfHour
            return ok((0..<(7 * 24)).map { forecastPoint(spot, at: start.addingTimeInterval(Double($0) * 3600)) })
        default:
            return problem(404, "not_found")
        }
    }

    private static func scoreJSON(_ spot: Spot, at date: Date) -> [String: Any] {
        let s = score(spot, at: date)
        return ["score": s.score, "confidence": 2, "capReason": nullable(s.cap),
                "reasons": reasons(s.cap), "computedAt": iso(.now)]
    }

    private static func reasons(_ cap: String?) -> [[String: Any]] {
        var list: [[String: Any]] = [["code": "weather.clear", "params": ["temp": 21]],
                                     ["code": "crowd.low", "params": [String: Any]()],
                                     ["code": "amenity.well_equipped", "params": [String: Any]()]]
        if let cap { list.insert(["code": "cap.\(cap)", "params": [String: Any]()], at: 0) }
        return list
    }

    private static func recommendation(_ spot: Spot, at date: Date) -> [String: Any] {
        ["id": spot.id.uuidString, "kind": spot.kind, "name": spot.name, "names": [String: String](),
         "coordinates": [spot.lon, spot.lat], "country": "NL", "city": "Amsterdam", "tz": timeZoneID,
         "lastVerifiedAt": iso(.now.addingTimeInterval(-40 * 86_400)), "distanceM": spot.distanceM,
         "score": scoreJSON(spot, at: date)]
    }

    private static func feature(_ spot: Spot, at date: Date, from: Date?, hours: Int?) -> [String: Any] {
        var properties: [String: Any] = [
            "id": spot.id.uuidString, "kind": spot.kind, "name": spot.name, "names": [String: String](),
            "country": "NL", "city": "Amsterdam", "tz": timeZoneID,
            "lastVerifiedAt": iso(.now.addingTimeInterval(-40 * 86_400)), "when": iso(date),
            "score": scoreJSON(spot, at: date),
        ]
        if let from, let hours {
            properties["scores"] = (0..<hours).map { i -> [String: Any] in
                let t = from.addingTimeInterval(Double(i) * 3600)
                let s = score(spot, at: t)
                return ["tsHour": iso(t), "score": s.score, "capReason": nullable(s.cap)]
            }
        }
        return ["type": "Feature", "geometry": ["type": "Point", "coordinates": [spot.lon, spot.lat]] as JSON,
                "properties": properties]
    }

    private static func detail(_ spot: Spot) -> [String: Any] {
        ["id": spot.id.uuidString, "kind": spot.kind, "name": spot.name, "names": [String: String](),
         "coordinates": [spot.lon, spot.lat], "country": "NL", "city": "Amsterdam", "tz": timeZoneID,
         "lastVerifiedAt": iso(.now.addingTimeInterval(-40 * 86_400)),
         "amenities": [JSON]([["type": "toilet", "distanceM": 120, "source": "osm"],
                       ["type": "water", "distanceM": 340, "source": "osm"],
                       ["type": "playground", "distanceM": 410, "source": "osm"],
                       ["type": "bicycle_parking", "distanceM": 60, "source": "osm"]]),
         "sources": [["source": "osm", "sourceId": "way/123", "version": 4, "importedAt": iso(.now)] as JSON],
         "weatherSource": "openmeteo"]
    }

    private static func forecastPoint(_ spot: Spot, at date: Date) -> [String: Any] {
        let s = score(spot, at: date)
        return ["tsHour": iso(date), "score": s.score,
                "components": ["weather": min(100, s.score + 4), "crowd": 70, "amenity": 55, "fresh": 80],
                "capReason": nullable(s.cap), "reasons": reasons(s.cap), "confidence": 2,
                "weather": ["tempC": 21.0, "feelsLikeC": 20.0, "precipProb": s.cap == "rain" ? 80 : 10,
                            "windKmh": 12.0, "uv": 4.0, "cloud": 30]] as JSON
    }

    /// `/v1/getaways`: two cities over the requested range, built from its
    /// `start` / `days` so any preset gets a valid answer. Amsterdam has no
    /// window on its second day (`weatherScore: null`). The top spot's total
    /// score is a little under the weather score, as it is in practice.
    private static func getaways(start: String?, days: Int) -> JSON {
        let first = start.flatMap { CivilDay(string: $0) } ?? CivilDay(.now, in: .current)
        let count = min(max(days, 1), 3)
        let items: [JSON] = [
            getawayCity(slug: "lisbon", name: "Lisbon", country: "PT", tz: "Europe/Lisbon",
                        center: [-9.14, 38.72], spot: "Jardim da Estrela", scores: [71, 86],
                        first: first, count: count),
            getawayCity(slug: "amsterdam", name: "Amsterdam", country: "NL", tz: "Europe/Amsterdam",
                        center: [4.89, 52.37], spot: "Vondelpark", scores: [74, nil],
                        first: first, count: count),
        ]
        return ["start": first.string, "days": count, "items": items, "computedAt": iso(.now)]
    }

    private static func getawayCity(slug: String, name: String, country: String, tz: String,
                                    center: [Double], spot: String, scores: [Int?],
                                    first: CivilDay, count: Int) -> JSON {
        let used: [Int?] = (0..<count).map { scores[$0 % scores.count] }
        let best = used.compactMap { $0 }.max() ?? 0
        let bestDay = first.adding(days: used.firstIndex { $0 == best } ?? 0)
        let begin = bestDay.date(in: TimeZone(identifier: "UTC") ?? .gmt).addingTimeInterval(12 * 3600)
        var dayScores: [JSON] = []
        for (offset, score) in used.enumerated() {
            let value: Any = score.map { $0 as Any } ?? NSNull()
            dayScores.append(["date": first.adding(days: offset).string, "weatherScore": value, "goodHours": 4])
        }
        let window: JSON = ["start": iso(begin), "end": iso(begin.addingTimeInterval(4 * 3600)), "weatherScore": best]
        let topSpot: JSON = ["id": "00000000-0000-4000-8000-0000000000b1", "name": spot, "score": max(best - 6, 0)]
        let reasons: [JSON] = [
            ["code": "getaway.dry_day", "params": JSON()],
            ["code": "getaway.long_window", "params": ["hours": 4]],
        ]
        var city: JSON = ["slug": slug, "name": name, "country": country, "tz": tz, "center": center]
        city["windowDays"] = used.compactMap { $0 }.count
        city["bestDay"] = bestDay.string
        city["window"] = window
        city["goodHours"] = 6
        city["dayScores"] = dayScores
        city["topSpot"] = topSpot
        city["reasons"] = reasons
        return city
    }

    /// `/v1/weather/nearby`: a mild day with a rain spell and one hour with
    /// only a temperature (every field but `ts` is optional).
    private static func nearbyWeatherPoint(at date: Date, index: Int) -> [String: Any] {
        let temp = 16.0 + 6.0 * sin(Double(index) / 24 * 2 * .pi)
        var point: [String: Any] = ["ts": iso(date), "tempC": (temp * 10).rounded() / 10]
        if index == 5 { return point }
        point["feelsLikeC"] = ((temp - 1.5) * 10).rounded() / 10
        point["precipProb"] = (6..<10).contains(index) ? 70 : (index % 4 == 0 ? 25 : 5)
        point["windKmh"] = 12.0
        point["uv"] = 3.0
        point["cloud"] = (6..<10).contains(index) ? 90 : 35
        return point
    }

    private static func alertRule() -> [String: Any] {
        ["id": "00000000-0000-4000-8000-0000000000a1", "deviceId": UUID().uuidString,
         "spotId": spots[1].id.uuidString, "h3Cell": NSNull(), "areaCenter": NSNull(), "radiusM": NSNull(),
         "minScore": 75, "daysMask": 65, "startLocal": "10:00", "endLocal": "18:00",
         "tz": timeZoneID, "enabled": true]
    }

    // MARK: Encoding helpers

    private static func ok(_ data: Any) -> (Int, Data) { raw(["data": data]) }

    private static func nullable(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private static func raw(_ object: Any) -> (Int, Data) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    private static func problem(_ status: Int, _ code: String) -> (Int, Data) {
        let body: [String: Any] = ["type": "about:blank", "code": code, "title": code, "status": status]
        return (status, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func parseISO(_ s: String) -> Date? { ISO8601DateFormatter().date(from: s) }
}

/// Answers every request from `UITestFixtures.response(for:)`.
final class FixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private let lock = NSLock()
    private var stopped = false

    override func startLoading() {
        let delay = UITestFixtures.responseDelay
        guard delay > 0 else { return answer() }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.answer() }
    }

    private func answer() {
        lock.lock()
        let isStopped = stopped
        lock.unlock()
        guard !isStopped else { return }
        if UITestFixtures.isOffline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (status, body) = UITestFixtures.response(for: request)
        let url = request.url ?? URL(string: "about:blank")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
