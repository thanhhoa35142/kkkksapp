import CryptoKit
import DeviceCheck
import Foundation

// MARK: - API

struct AttestChallengeResponse: Decodable {
    let challenge: String
    let expiresAt: Date
    /// false: the server has no App Attest config yet — don't spend a key.
    let configured: Bool
}

struct AttestRequest: Encodable {
    var keyId: String?
    var attestation: String?
    var unsupported: Bool?
}

struct AttestStatusResponse: Decodable {
    let status: String
}

extension APIClient {
    /// `POST /v1/devices/{id}/attest/challenge` — single use, ~5 minutes.
    func attestChallenge(deviceID: UUID) async throws -> AttestChallengeResponse {
        try await send(.post, "/v1/devices/\(deviceID.uuidString)/attest/challenge", body: EmptyBody())
    }

    /// `POST /v1/devices/{id}/attest` — the server records the outcome.
    func attest(deviceID: UUID, _ request: AttestRequest) async throws -> String {
        let response: AttestStatusResponse = try await send(
            .post, "/v1/devices/\(deviceID.uuidString)/attest", body: request)
        return response.status
    }
}

// MARK: - App Attest

/// Proves to the backend that requests come from this app on a genuine Apple
/// device (DCAppAttestService). Runs after the device is registered until the
/// server has recorded `verified` (or `unsupported`) for this device id.
/// The server is in monitor mode, so nothing in the app depends on the
/// outcome and every failure is silent (retried at most daily).
///
/// Every attempt uses a fresh key: a key can be attested only once, so a
/// key from an attempt that failed half-way (network, rejection, a new
/// device id after "Delete my data") can never be reused.
enum AppAttestor {
    private enum Key {
        /// Device id the server recorded a final outcome for.
        static let doneForDevice = "appAttest.doneForDevice"
        static let lastAttemptAt = "appAttest.lastAttemptAt"
    }

    private static var defaults: UserDefaults { .standard }

    static func attestIfNeeded(api: APIClient, now: Date = .now) async {
        let deviceID = DeviceIdentity.deviceID
        guard DeviceIdentity.deviceSecret != nil,
              defaults.string(forKey: Key.doneForDevice) != deviceID.uuidString
        else { return }
        if let last = defaults.object(forKey: Key.lastAttemptAt) as? Date,
           now.timeIntervalSince(last) < 24 * 3600 { return }
        defaults.set(now, forKey: Key.lastAttemptAt)

        do {
            guard let status = try await attest(api: api, deviceID: deviceID) else {
                Log.api.info("app attest: server not configured, retrying later")
                return
            }
            if status == "verified" || status == "unsupported" {
                defaults.set(deviceID.uuidString, forKey: Key.doneForDevice)
            }
            Log.api.info("app attest: \(status, privacy: .public)")
        } catch {
            Log.api.error("app attest failed: \(error.localizedDescription)")
        }
    }

    /// nil when the server cannot verify yet (no key is generated then).
    private static func attest(api: APIClient, deviceID: UUID) async throws -> String? {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            return try await api.attest(deviceID: deviceID, AttestRequest(unsupported: true))
        }
        let challenge = try await api.attestChallenge(deviceID: deviceID)
        guard challenge.configured, let raw = Data(base64Encoded: challenge.challenge) else { return nil }
        let keyID = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: raw))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        return try await api.attest(deviceID: deviceID, AttestRequest(
            keyId: keyID, attestation: attestation.base64EncodedString()))
    }
}
