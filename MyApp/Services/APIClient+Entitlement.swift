import Foundation

// MARK: - Entitlement

extension APIClient {
    /// `GET /v1/devices/{id}/entitlement` — resolved plan for a device.
    func entitlement(deviceID: UUID) async throws -> Entitlement {
        try await get("/v1/devices/\(deviceID.uuidString)/entitlement", enveloped: true)
    }

    /// `POST /v1/entitlement/link` — attach a StoreKit signed transaction (JWS)
    /// after purchase or restore. Returns the resolved plan.
    @discardableResult
    func linkTransaction(deviceID: UUID, signedTransaction: String) async throws -> String {
        let request = LinkTransactionRequest(deviceId: deviceID, signedTransaction: signedTransaction)
        let response: LinkTransactionResponse = try await send(.post, "/v1/entitlement/link", body: request)
        return response.plan
    }
}
