import XCTest
@testable import MyApp

/// Best Now's per-row time line and the Free-plan hour window.
final class HourOutlookTests: XCTestCase {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    /// 10:00 local on 2026-06-06 (a Saturday) = 08:00Z.
    private var base: Date { ISO8601DateFormatter().date(from: "2026-06-06T08:00:00Z")! }

    private func hours(_ scores: [Int], caps: [Int: String] = [:]) -> [HourOutlook.Hour] {
        scores.enumerated().map { i, s in
            HourOutlook.Hour(tsHour: base.addingTimeInterval(Double(i) * 3600), score: s, capReason: caps[i])
        }
    }

    func testBetterLaterPicksBestEarliestHour() {
        let outlook = HourOutlook.make(hours: hours([62, 70, 88, 88, 60]), from: base, current: 62, timeZone: amsterdam)
        XCTAssertEqual(outlook, .betterAt(hour: base.addingTimeInterval(2 * 3600), score: 88))
    }

    func testSmallGainIsNotWorthMoving() {
        let outlook = HourOutlook.make(hours: hours([80, 83, 70, 50]), from: base, current: 80, timeZone: amsterdam)
        XCTAssertEqual(outlook, .goodUntil(end: base.addingTimeInterval(3 * 3600)))
    }

    func testGoodThroughWhenDataEndsGood() {
        let outlook = HourOutlook.make(hours: hours([75, 74, 72]), from: base, current: 75, timeZone: amsterdam)
        XCTAssertEqual(outlook, .goodThrough(last: base.addingTimeInterval(2 * 3600)))
    }

    func testDarkHoursEndTheGoodRunAndAreNeverBetter() {
        let outlook = HourOutlook.make(hours: hours([70, 68, 95]), caps: [2: "dark"],
                                       from: base, current: 70, timeZone: amsterdam)
        XCTAssertEqual(outlook, .goodUntil(end: base.addingTimeInterval(2 * 3600)))
    }

    func testPoorAndNoBetterLater() {
        let outlook = HourOutlook.make(hours: hours([40, 35, 30]), from: base, current: 40, timeZone: amsterdam)
        XCTAssertEqual(outlook, .noBetterToday)
    }

    func testStopsAtTheSpotsLocalMidnight() {
        // 22:00 local, then 23:00, then 00:00 next day scoring 90 — not "later today".
        let late = ISO8601DateFormatter().date(from: "2026-06-06T20:00:00Z")!
        let series = [50, 45, 90].enumerated().map { i, s in
            HourOutlook.Hour(tsHour: late.addingTimeInterval(Double(i) * 3600), score: s, capReason: nil)
        }
        XCTAssertEqual(HourOutlook.make(hours: series, from: late, current: 50, timeZone: amsterdam), .noBetterToday)
    }

    func testNoDataNoLine() {
        XCTAssertNil(HourOutlook.make(hours: [], from: base, current: 70, timeZone: amsterdam))
    }

    func testFreeWindowStopsBeforeDayAfterTomorrow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = amsterdam
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 9))!
        let tomorrow2200 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 7, hour: 22))!
        XCTAssertEqual(HourWindow.hours(from: tomorrow2200, isPlus: false, now: now, calendar: calendar), 2)
        XCTAssertEqual(HourWindow.hours(from: tomorrow2200, isPlus: true, now: now, calendar: calendar), 12)
        XCTAssertEqual(HourWindow.hours(from: now, isPlus: false, now: now, calendar: calendar), 12)
    }
}
