import Foundation

struct ReportStatus: Decodable {
    let status: String // "accepted" | "duplicate"
}

struct SpotReportRequest: Encodable {
    let deviceId: UUID
    let type: String // confirm | missing | closed | issue
    var issueCode: String?
}

struct CrowdReportRequest: Encodable {
    let deviceId: UUID
    let level: Int // 1 quiet, 2 moderate, 3 busy
}

struct ScoreFeedbackRequest: Encodable {
    let deviceId: UUID
    let spotId: UUID
    let tsHour: Date
    let verdict: Int // -1, 0, +1
}
