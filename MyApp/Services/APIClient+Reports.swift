import Foundation

// MARK: - Reports & feedback

extension APIClient {
    /// `POST /v1/spots/{id}/reports`
    @discardableResult
    func submitSpotReport(spotID: UUID, deviceID: UUID, type: String, issueCode: String? = nil) async throws -> String {
        let request = SpotReportRequest(deviceId: deviceID, type: type, issueCode: issueCode)
        let status: ReportStatus = try await send(.post, "/v1/spots/\(spotID.uuidString)/reports", body: request)
        return status.status
    }

    /// `POST /v1/spots/{id}/crowd-reports` — call only when user is near the spot.
    @discardableResult
    func submitCrowdReport(spotID: UUID, deviceID: UUID, level: Int) async throws -> String {
        let request = CrowdReportRequest(deviceId: deviceID, level: level)
        let status: ReportStatus = try await send(.post, "/v1/spots/\(spotID.uuidString)/crowd-reports", body: request)
        return status.status
    }

    /// `POST /v1/scores/feedback`
    @discardableResult
    func submitScoreFeedback(spotID: UUID, deviceID: UUID, tsHour: Date, verdict: Int) async throws -> String {
        let request = ScoreFeedbackRequest(deviceId: deviceID, spotId: spotID, tsHour: tsHour, verdict: verdict)
        let status: ReportStatus = try await send(.post, "/v1/scores/feedback", body: request)
        return status.status
    }
}
