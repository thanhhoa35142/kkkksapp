import CoreLocation
import XCTest
@testable import MyApp

final class NewFeaturesTests: XCTestCase {
    // MARK: Deep links

    func testSpotLinkRoundTrip() {
        let id = UUID()
        XCTAssertEqual(SpotLink.spotID(from: SpotLink.appURL(spotID: id)), id)
        XCTAssertEqual(SpotLink.appURL(spotID: id), WidgetBridge.spotURL(id))
        XCTAssertNil(SpotLink.spotID(from: URL(string: "https://maps.apple.com/?q=x")!))
        XCTAssertNil(SpotLink.spotID(from: URL(string: "pickhour://other/\(id.uuidString)")!))
    }

    // MARK: Crowd report proximity

    func testCrowdProximityByKind() {
        let spot = CLLocationCoordinate2D(latitude: 52.3580, longitude: 4.8686)
        // ~400 m north.
        let here = CLLocationCoordinate2D(latitude: 52.3616, longitude: 4.8686)
        XCTAssertTrue(CrowdProximity.isNear(here, spot: spot, kind: "park"))
        XCTAssertFalse(CrowdProximity.isNear(here, spot: spot, kind: "table"))
    }

    func testCrowdReportLogOnePerHour() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.crowd.\(UUID())"))
        let spot = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(CrowdReportLog.level(spotID: spot, now: now, defaults: defaults))
        CrowdReportLog.record(3, spotID: spot, now: now, defaults: defaults)
        XCTAssertEqual(CrowdReportLog.level(spotID: spot, now: now, defaults: defaults), 3)
        XCTAssertNil(CrowdReportLog.level(spotID: spot, now: now.addingTimeInterval(3600), defaults: defaults))
    }

    // MARK: Area alerts

    func testAreaPointIsCoarse() throws {
        let p = AreaPoint(coarse: 52.36789, 4.88123)
        XCTAssertEqual(p.lat, 52.37, accuracy: 1e-9)
        XCTAssertEqual(p.lon, 4.88, accuracy: 1e-9)
        let body = try JSONEncoder().encode(AlertRuleRequest(
            deviceId: UUID(), spotId: nil, h3Cell: nil, area: p, radiusM: 3000,
            minScore: 70, daysMask: 65, startLocal: "10:00", endLocal: "18:00", tz: "Europe/Amsterdam", enabled: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["spotId"])   // exactly one target is sent
        XCTAssertNil(json["h3Cell"])
        XCTAssertNotNil(json["area"])
    }

    func testAlertRuleDecodesAreaCenter() throws {
        let json = """
        {"id":"\(UUID())","deviceId":"\(UUID())","spotId":null,"h3Cell":608432992271990783,
         "areaCenter":{"lat":52.359,"lon":4.88},"radiusM":3000,"minScore":50,"daysMask":127,
         "startLocal":"08:00","endLocal":"10:00","tz":"Europe/Amsterdam","enabled":true}
        """
        let rule = try JSONDecoder().decode(AlertRule.self, from: Data(json.utf8))
        XCTAssertTrue(rule.isArea)
        XCTAssertEqual(rule.areaCenter?.lat, 52.359)
    }

    // MARK: Week strip

    func testWeekStripBestPerDayAndLocks() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func point(_ iso: String, _ score: Int) throws -> ForecastPoint {
            try decoder.decode(ForecastPoint.self, from: Data(
                #"{"tsHour":"\#(iso)","score":\#(score),"components":{},"capReason":null,"reasons":[],"confidence":2}"#.utf8))
        }
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let pts = [try point("2027-01-15T10:00:00Z", 50), try point("2027-01-15T13:00:00Z", 81),
                   try point("2027-01-15T15:00:00Z", 81)]
        let days = WeekStrip.days(from: [day1, day2], points: { $0 == day1 ? pts : [] }, locked: { $0 >= 1 })
        XCTAssertEqual(days[0].best?.score, 81)
        XCTAssertEqual(days[0].best?.tsHour, pts[1].tsHour) // earlier of the tie
        XCTAssertFalse(days[0].locked)
        XCTAssertNil(days[1].best)
        XCTAssertTrue(days[1].locked)
    }

    // MARK: Dark state

    func testNextMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 22))!
        let early = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 3))!
        guard case .at(let a) = BestNowModel.nextMorning(now: night, calendar: calendar),
              case .at(let b) = BestNowModel.nextMorning(now: early, calendar: calendar) else {
            return XCTFail("expected a concrete hour")
        }
        XCTAssertEqual(calendar.component(.day, from: a), 14)
        XCTAssertEqual(calendar.component(.hour, from: a), 10)
        XCTAssertEqual(calendar.component(.day, from: b), 14)
    }
}
