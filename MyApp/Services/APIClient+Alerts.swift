import Foundation

// MARK: - Alerts

extension APIClient {
    /// `GET /v1/alerts?deviceId=` — all rules for a device.
    func alerts(deviceID: UUID) async throws -> [AlertRule] {
        let list: AlertRuleList = try await get(
            "/v1/alerts",
            query: [URLQueryItem(name: "deviceId", value: deviceID.uuidString)],
            enveloped: true
        )
        return list.items
    }

    /// `POST /v1/alerts` — 403 `plan_limit` when the device's plan is exhausted.
    @discardableResult
    func createAlert(_ request: AlertRuleRequest) async throws -> AlertRule {
        try await send(.post, "/v1/alerts", body: request)
    }

    /// `PUT /v1/alerts/{id}` — full replace of a rule.
    @discardableResult
    func updateAlert(id: UUID, _ request: AlertRuleRequest) async throws -> AlertRule {
        try await send(.put, "/v1/alerts/\(id.uuidString)", body: request)
    }

    /// `DELETE /v1/alerts/{id}?deviceId=` — 204 No Content.
    func deleteAlert(id: UUID, deviceID: UUID) async throws {
        try await delete(
            "/v1/alerts/\(id.uuidString)",
            query: [URLQueryItem(name: "deviceId", value: deviceID.uuidString)]
        )
    }
}
