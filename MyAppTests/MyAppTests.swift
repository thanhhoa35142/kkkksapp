import XCTest
@testable import MyApp

final class MyAppTests: XCTestCase {

    func testAPIProblemDecodes() throws {
        let json = """
        {"type":"about:blank","code":"not_found","title":"Spot not found","status":404,"instance":"/v1/spots/x","requestId":"abc"}
        """.data(using: .utf8)!
        let problem = try JSONDecoder().decode(APIProblem.self, from: json)
        XCTAssertEqual(problem.code, "not_found")
        XCTAssertEqual(problem.requestId, "abc")
    }

    func testForecastPointDecodes() throws {
        let json = """
        {"tsHour":"2026-11-11T14:00:00Z","score":62,"components":{"weather":80,"crowd":44},"capReason":null,"reasons":[{"code":"weather.clear","params":{"temp":21}}],"confidence":2}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let point = try decoder.decode(ForecastPoint.self, from: json)
        XCTAssertEqual(point.score, 62)
        XCTAssertEqual(point.components.weather, 80)
        XCTAssertNil(point.components.shade) // absent = missing data
        XCTAssertEqual(point.reasons.first?.code, "weather.clear")
    }

    func testEnvelopeDecodes() throws {
        let json = """
        {"data":{"status":"accepted"}}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(Envelope<ReportStatus>.self, from: json)
        XCTAssertEqual(status.data.status, "accepted")
    }
}
