import Foundation

// MARK: - Good-day push (all users)

extension APIClient {
    /// `GET /v1/devices/{id}/nudge`. nil when the device has no subscription
    /// (404 `not_found`).
    func nudge(deviceID: UUID) async throws -> NudgeSubscription? {
        do {
            let subscription: NudgeSubscription = try await get("/v1/devices/\(deviceID.uuidString)/nudge", enveloped: true)
            return subscription
        } catch let error as APIError where error.code == "not_found" {
            return nil
        }
    }

    /// `PUT /v1/devices/{id}/nudge` — create or update. `home` is optional on
    /// updates; it is already rounded (`NudgeHome`). Free and Plus alike.
    @discardableResult
    func setNudge(deviceID: UUID, enabled: Bool, consent: NudgeConsent,
                  home: NudgeHome?, sendHour: Int? = nil) async throws -> NudgeSubscription {
        try await send(.put, "/v1/devices/\(deviceID.uuidString)/nudge",
                       body: NudgeRequest(enabled: enabled, consent: consent, home: home, sendHour: sendHour))
    }

    /// Opt out. 204.
    func deleteNudge(deviceID: UUID) async throws {
        try await delete("/v1/devices/\(deviceID.uuidString)/nudge")
    }
}
