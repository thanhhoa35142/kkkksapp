import Foundation

// MARK: - Product events

extension APIClient {
    /// `POST /v1/events` — batch ingest (202 Accepted). 1–100 events per call.
    /// Never include location or PII in event props.
    @discardableResult
    func trackEvents(deviceID: UUID, events: [AppEvent]) async throws -> TrackEventsResponse {
        let request = TrackEventsRequest(deviceId: deviceID, events: events)
        return try await send(.post, "/v1/events", body: request)
    }
}
