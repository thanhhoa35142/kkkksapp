import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// App lifecycle hooks SwiftUI does not expose: notification delegate wiring
/// and the APNs token callbacks. One class per platform, same behavior.
#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushManager.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.api.error("APNs registration failed: \(error.localizedDescription)")
    }
}
#elseif os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushManager.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.api.error("APNs registration failed: \(error.localizedDescription)")
    }
}
#endif
