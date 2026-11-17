import Foundation

// MARK: - Devices

extension APIClient {
    /// `POST /v1/devices` — first call for a fresh install returns
    /// `deviceSecret` once; it is stored in the Keychain and sent as
    /// `X-Device-Token` on every device-scoped request after that.
    @discardableResult
    func registerDevice(_ request: DeviceRegisterRequest) async throws -> UUID {
        let response: DeviceIDResponse = try await send(.post, "/v1/devices", body: request)
        if let secret = response.deviceSecret {
            DeviceIdentity.deviceSecret = secret
        }
        return response.id
    }

    /// `DELETE /v1/devices/{id}` — 204 No Content, no body to decode.
    func deleteDevice(id: UUID) async throws {
        try await delete("/v1/devices/\(id.uuidString)")
    }
}
