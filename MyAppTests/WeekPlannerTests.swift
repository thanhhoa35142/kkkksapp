import XCTest
@testable import MyApp

final class WeekPlannerTests: XCTestCase {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
    private let spot = UUID()

    /// Hourly points from `start` (UTC ISO) with the given scores.
    private func points(from start: String, _ scores: [Int]) throws -> [ForecastPoint] {
        let base = try XCTUnwrap(ISO8601DateFormatter().date(from: start))
        let iso = ISO8601DateFormatter()
        let items = scores.enumerated().map { i, s in
            #"{"tsHour":"\#(iso.string(from: base.addingTimeInterval(Double(i) * 3600)))","score":\#(s),"components":{},"capReason":null,"reasons":[],"confidence":2}"#
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ForecastPoint].self, from: Data("[\(items.joined(separator: ","))]".utf8))
    }

    private func local(_ date: Date) -> Int {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = amsterdam
        return c.component(.hour, from: date)
    }

    func testPicksPeakAndGrowsWithinFivePoints() throws {
        // Sat 2026-11-21, Amsterdam = UTC+1. 08:00 local = 07:00Z.
        // Local 08..19: low morning, peak 15–16, shoulders 14 and 17 close.
        let scores = [40, 45, 50, 62, 64, 70, 84, 88, 90, 86, 70, 55]
        let pts = try points(from: "2026-11-21T07:00:00Z", scores)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let days = WeekPlanner.bestPerDay(pts, spotID: spot, spotName: "Vondelpark", timeZone: amsterdam, now: now)
        let w = try XCTUnwrap(days.first)
        XCTAssertEqual(days.count, 1)
        // Peak 15–17 (89), grows to 17:00 (86) then 14:00 (84 = floor); 13 and 18 (70) stop it.
        XCTAssertEqual(local(w.start), 14)
        XCTAssertEqual(local(w.end), 18)
        XCTAssertEqual(w.score, 87)
    }

    func testNoWindowBelowThreshold() throws {
        let pts = try points(from: "2026-11-21T07:00:00Z", [59, 59, 70, 50, 59, 59])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        XCTAssertTrue(WeekPlanner.bestPerDay(pts, spotID: spot, spotName: "X", timeZone: amsterdam, now: now).isEmpty)
    }

    func testIgnoresNightAndPastHours() throws {
        // Local 20:00–23:00 all 95 → outside daylight window.
        let pts = try points(from: "2026-11-21T19:00:00Z", [95, 95, 95, 95])
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        XCTAssertTrue(WeekPlanner.bestPerDay(pts, spotID: spot, spotName: "X", timeZone: amsterdam, now: now).isEmpty)

        // Good hours, but already past.
        let past = try points(from: "2026-11-21T09:00:00Z", [90, 90, 90])
        let later = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-21T15:00:00Z"))
        XCTAssertTrue(WeekPlanner.bestPerDay(past, spotID: spot, spotName: "X", timeZone: amsterdam, now: later).isEmpty)
    }

    func testCapsAtMaxHours() throws {
        let pts = try points(from: "2026-11-21T07:00:00Z", Array(repeating: 80, count: 12))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z"))
        let w = try XCTUnwrap(WeekPlanner.bestPerDay(pts, spotID: spot, spotName: "X", timeZone: amsterdam, now: now).first)
        XCTAssertEqual(w.hours, WeekPlanner.maxHours)
    }

    func testAcrossPlacesKeepsBestPerDay() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let a = PlanWindow(spotID: UUID(), spotName: "A", timeZone: .current, start: day, end: day.addingTimeInterval(7200), score: 70)
        let b = PlanWindow(spotID: UUID(), spotName: "B", timeZone: .current, start: day.addingTimeInterval(3600), end: day.addingTimeInterval(14400), score: 85)
        XCTAssertEqual(WeekPlanModel.bestPerDay([a, b]).map(\.spotName), ["B"])
    }
}
