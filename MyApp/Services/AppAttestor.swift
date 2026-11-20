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
/// device (DCAppAttestService).
///
/// 1. Attestation: after registration, a fresh key is attested once; when
///    the server answers `verified` its id is kept for this device id.
/// 2. Assertions: covered POSTs (`AppAssertionRoutes`) are signed with that
///    key in `X-App-Assertion` (see `APIClient.send`).
///
/// The server runs these in monitor mode per route group until it enforces
/// them, so failures here are silent (attestation retried at most daily, or
/// right away when an enforced route answers `attest_required`).
///
/// Every attestation uses a fresh key: a key can be attested only once, so a
/// key from an attempt that failed half-way can never be reused.
enum AppAttestor {
    private enum Key {
        /// Verified key id and the device id it belongs to.
        static let keyID = "appAttest.keyId"
        static let keyDevice = "appAttest.keyDevice"
        /// Device id the server recorded `unsupported` for.
        static let unsupportedForDevice = "appAttest.unsupportedForDevice"
        static let lastAttemptAt = "appAttest.lastAttemptAt"
        static let lastForcedAt = "appAttest.lastForcedAt"
    }

    private static var defaults: UserDefaults { .standard }

    /// Attests unless this device already has a verified key. `force` (an
    /// enforced route answered `attest_required`): the server doesn't know
    /// our key, so a new one is attested now — at most once a minute.
    /// Returns true when a key the server verified is in place.
    @discardableResult
    static func attestIfNeeded(api: APIClient, now: Date = .now, force: Bool = false) async -> Bool {
        let deviceID = DeviceIdentity.deviceID
        let id = deviceID.uuidString
        guard DeviceIdentity.deviceSecret != nil else { return false }
        if force {
            // Throttled: a concurrent forced attempt may just have stored a key.
            if let last = defaults.object(forKey: Key.lastForcedAt) as? Date,
               now.timeIntervalSince(last) < 60 { return defaults.string(forKey: Key.keyDevice) == id }
            defaults.set(now, forKey: Key.lastForcedAt)
            forgetKey()
        } else {
            if defaults.string(forKey: Key.keyDevice) == id
                || defaults.string(forKey: Key.unsupportedForDevice) == id { return false }
            if let last = defaults.object(forKey: Key.lastAttemptAt) as? Date,
               now.timeIntervalSince(last) < 24 * 3600 { return false }
        }
        defaults.set(now, forKey: Key.lastAttemptAt)

        do {
            guard let result = try await attest(api: api, deviceID: deviceID) else {
                Log.api.info("app attest: server not configured, retrying later")
                return false
            }
            let (status, keyID) = result
            Log.api.info("app attest: \(status, privacy: .public)")
            switch status {
            case "verified":
                defaults.set(keyID, forKey: Key.keyID)
                defaults.set(id, forKey: Key.keyDevice)
                return keyID != nil
            case "unsupported":
                defaults.set(id, forKey: Key.unsupportedForDevice)
            default:
                break
            }
        } catch {
            Log.api.error("app attest failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
        return false
    }

    /// `X-App-Assertion` for one request, or nil without a verified key.
    /// Signs SHA256(METHOD "\n" PATH "\n" BODY) — the server rebuilds the
    /// same bytes from the request it receives.
    static func assertion(method: String, path: String, body: Data) async -> String? {
        let service = DCAppAttestService.shared
        guard service.isSupported,
              defaults.string(forKey: Key.keyDevice) == DeviceIdentity.deviceID.uuidString,
              let keyID = defaults.string(forKey: Key.keyID)
        else { return nil }
        var clientData = Data("\(method)\n\(path)\n".utf8)
        clientData.append(body)
        do {
            let assertion = try await service.generateAssertion(
                keyID, clientDataHash: Data(SHA256.hash(data: clientData)))
            return assertion.base64EncodedString()
        } catch let error as DCError where error.code == .invalidKey {
            // Key gone (e.g. restored backup): attest a new one next time.
            Log.api.info("app attest: key invalid, re-attesting later")
            forgetKey()
            return nil
        } catch {
            Log.api.error("app assertion failed: \(ErrorSummary.describe(error), privacy: .public)")
            return nil
        }
    }

    private static func forgetKey() {
        defaults.removeObject(forKey: Key.keyID)
        defaults.removeObject(forKey: Key.keyDevice)
        defaults.removeObject(forKey: Key.lastAttemptAt)
    }

    /// (status, keyId) — nil when the server cannot verify yet (no key is
    /// generated then). keyId is nil for `unsupported`.
    private static func attest(api: APIClient, deviceID: UUID) async throws -> (String, String?)? {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            return (try await api.attest(deviceID: deviceID, AttestRequest(unsupported: true)), nil)
        }
        let challenge = try await api.attestChallenge(deviceID: deviceID)
        guard challenge.configured, let raw = Data(base64Encoded: challenge.challenge) else { return nil }
        let keyID = try await service.generateKey()
        let clientDataHash = Data(SHA256.hash(data: raw))
        let attestation = try await service.attestKey(keyID, clientDataHash: clientDataHash)
        let status = try await api.attest(deviceID: deviceID, AttestRequest(
            keyId: keyID, attestation: attestation.base64EncodedString()))
        return (status, keyID)
    }
}
