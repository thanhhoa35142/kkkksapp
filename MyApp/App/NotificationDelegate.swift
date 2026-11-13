import Foundation
import UserNotifications

/// UNUserNotificationCenter delegate — decides how notifications appear while
/// the app is foregrounded and routes taps to in-app destinations.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show banners + sound even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Notification tapped — route to the spot if the payload carries one.
    /// Payload contract (backend notifier.Payload): top-level "kind",
    /// "spotId", "score", "windowStart" next to "aps". Kinds: "alert.window"
    /// (score alert, + "ruleId") and "digest.weekend" (Thursday plan, + "windowEnd").
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let kind = userInfo["kind"] as? String,
              ["alert.window", "digest.weekend"].contains(kind) else { return }
        let spotID = (userInfo["spotId"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            DeepLinkRouter.shared.handle(spotID: spotID)
        }
    }
}
