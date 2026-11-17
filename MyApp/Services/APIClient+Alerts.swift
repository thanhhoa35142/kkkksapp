import Foundation

// MARK: - Alerts

extension APIClient {
    /// `GET /v1/alerts` — all rules for this device (X-Device-ID/X-Device-Token headers).
    func alerts() async throws -> [AlertRule] {
        // deviceID travels in X-Device-ID/X-Device-Token headers.
        let list: AlertRuleList = try await get("/v1/alerts", enveloped: true)
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

    /// `DELETE /v1/alerts/{id}` — 204 No Content.
    func deleteAlert(id: UUID) async throws {
        try await delete("/v1/alerts/\(id.uuidString)")
    }
}
