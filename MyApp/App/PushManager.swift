import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Push notification lifecycle: permission prompt, APNs registration and
/// syncing the device token to the backend.
///
/// Call `requestAuthorization()` contextually (e.g. when the user creates
/// their first alert) — never at cold launch.
@MainActor
final class PushManager {
    static let shared = PushManager()

    /// "deviceID|env|token" last accepted by `POST /v1/devices`.
    private static let registeredTokenKey = "push.registeredToken"

    private init() {}

    /// Returns whether the user granted alert permission.
    ///
    /// Always asks for the full set of options, so it also upgrades a
    /// `.provisional` grant (set outside the app): iOS shows the system
    /// prompt then. Callers must never skip this call because the status
    /// is `.provisional` — alerts would stay quiet.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.api.error("notification authorization failed: \(ErrorSummary.describe(error), privacy: .public)")
            return false
        }
    }

    /// Current authorization status without prompting.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Registers with APNs if permission was granted. Token arrives later via
    /// `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func registerIfAuthorized() async {
        let status = await authorizationStatus()
        #if os(iOS)
        let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional, .ephemeral]
        #else
        let allowed: Set<UNAuthorizationStatus> = [.authorized, .provisional]  // no .ephemeral on macOS
        #endif
        guard allowed.contains(status) else { return }
        await MainActor.run {
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(macOS)
            NSApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }

    /// Called by AppDelegate with the raw APNs token. Persists it and syncs
    /// the device record so alerts can reach this install.
    ///
    /// iOS hands the token back on every launch (`registerIfAuthorized`),
    /// usually unchanged. Re-registering each time doubled the launch's
    /// `POST /v1/devices`, which the server limits per IP (30/hour) — so a
    /// carrier NAT or shared Wi-Fi ran out for everyone behind it. Skipped
    /// when this device id already registered this token and environment;
    /// `AppState.registerDevice()` sends the stored token on launch anyway.
    func handleDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        KeychainStore.set(token, for: .apnsToken)
        // Xcode debug builds hit the sandbox APNs environment.
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        KeychainStore.set(env, for: .apnsEnv)

        let registration = "\(DeviceIdentity.deviceID.uuidString)|\(env)|\(token)"
        if UserDefaults.standard.string(forKey: Self.registeredTokenKey) == registration { return }

        do {

            _ = try await AppConfig.apiClient.registerDevice(DeviceRegisterRequest(
                id: DeviceIdentity.deviceID,
                apnsToken: token,
                apnsEnv: env,
                locale: Locale.preferredLanguages.first,
                tz: TimeZone.current.identifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ))
            UserDefaults.standard.set(registration, forKey: Self.registeredTokenKey)
            Log.api.info("device registered for push, token \(token.prefix(8))…")
        } catch {
            Log.api.error("device registration failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }
}
