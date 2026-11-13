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

    private init() {}

    /// Returns whether the user granted alert permission.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.api.error("notification authorization failed: \(error.localizedDescription)")
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
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
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
    func handleDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        KeychainStore.set(token, for: .apnsToken)

        do {
            let env = await MainActor.run {
                // Xcode debug builds hit the sandbox APNs environment.
                #if DEBUG
                return "sandbox"
                #else
                return "production"
                #endif
            }
            KeychainStore.set(env, for: .apnsEnv)

            _ = try await AppConfig.apiClient.registerDevice(DeviceRegisterRequest(
                id: DeviceIdentity.deviceID,
                apnsToken: token,
                apnsEnv: env,
                locale: Locale.preferredLanguages.first,
                tz: TimeZone.current.identifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ))
            Log.api.info("device registered for push, token \(token.prefix(8))…")
        } catch {
            Log.api.error("device registration failed: \(error.localizedDescription)")
        }
    }
}
