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

    /// Notification tapped — route by payload (`NotificationRoute`).
    /// Payload contract (backend notifier.Payload): top-level "kind",
    /// "spotId", "score", "windowStart" next to "aps". Kinds: "alert.window"
    /// (score alert, + "ruleId"), "digest.weekend" (Thursday plan, + "windowEnd"),
    /// "nudge.goodday" (good-day tip, + "slot" "day" | "weekend", "windowEnd";
    /// opens the spot at "windowStart"), "plan.changed" / "plan.confirmed"
    /// (+ "planId", "shareToken", window, state).
    /// Copy is not in the payload: "aps.alert" carries `title-loc-key` /
    /// `loc-key` / `loc-args`, resolved from Localizable.xcstrings (`push.*`).
    /// Every routed tap is tracked as `push_opened` with the kind.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Read the payload here; only Sendable values cross to the main actor.
        let userInfo = response.notification.request.content.userInfo
        guard let route = NotificationRoute.route(userInfo) else { return }
        // Kind only (a known one: it routed) — no spot, place or time.
        if let kind = userInfo["kind"] as? String {
            await EventQueue.shared.enqueue(AppEvent(name: "push_opened", props: ["kind": .string(kind)]))
        }
        await MainActor.run {
            switch route {
            case .spot(let spotID): DeepLinkRouter.shared.handle(spotID: spotID)
            case .spotAt(let spotID, let hour): DeepLinkRouter.shared.handle(spotID: spotID, hour: hour)
            case .plan(let target): DeepLinkRouter.shared.handle(plan: target)
            }
        }
    }
}
