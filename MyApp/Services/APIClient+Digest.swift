import Foundation

// MARK: - Weekend plan push (Plus)

/// `GET/PUT/DELETE /v1/devices/{id}/digest` — Thursday-evening push with the
/// best weekend window across the chosen places. Server sends it in the
/// device's time zone (`sendDow` 0 = Sunday, `sendHour` local).
struct WeeklyDigest: Codable, Equatable {
    var spotIds: [UUID]
    var enabled: Bool
    var sendDow: Int?
    var sendHour: Int?
    /// PUT only: saved places the server dropped (no longer in our data).
    var skippedIds: [UUID]?
}

private struct WeeklyDigestRequest: Encodable {
    let spotIds: [UUID]
    let enabled: Bool
}

extension APIClient {
    /// nil when the device has no digest (404 `not_found`).
    func weeklyDigest(deviceID: UUID) async throws -> WeeklyDigest? {
        do {
            let digest: WeeklyDigest = try await get("/v1/devices/\(deviceID.uuidString)/digest", enveloped: true)
            return digest
        } catch let error as APIError where error.code == "not_found" {
            return nil
        }
    }

    /// 403 `plan_limit` on the Free plan. Server keeps at most 20 places.
    @discardableResult
    func setWeeklyDigest(deviceID: UUID, spotIDs: [UUID], enabled: Bool) async throws -> WeeklyDigest {
        try await send(.put, "/v1/devices/\(deviceID.uuidString)/digest",
                       body: WeeklyDigestRequest(spotIds: Array(spotIDs.prefix(20)), enabled: enabled))
    }

    func deleteWeeklyDigest(deviceID: UUID) async throws {
        try await delete("/v1/devices/\(deviceID.uuidString)/digest")
    }
}
