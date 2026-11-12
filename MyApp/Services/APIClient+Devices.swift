import Foundation

// MARK: - Devices

extension APIClient {
    /// `POST /v1/devices`
    @discardableResult
    func registerDevice(_ request: DeviceRegisterRequest) async throws -> UUID {
        let response: DeviceIDResponse = try await send(.post, "/v1/devices", body: request)
        return response.id
    }

    /// `DELETE /v1/devices/{id}` — 204 No Content, no body to decode.
    func deleteDevice(id: UUID) async throws {
        try await delete("/v1/devices/\(id.uuidString)")
    }
}
