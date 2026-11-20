import Foundation
#if os(iOS)
import UIKit
#endif

/// Runs `operation` under a background-task assertion so work started in the
/// foreground (a request, an event flush) can finish after the user leaves
/// the app instead of being suspended and failing with -1001/-1005 on
/// resume. When iOS is about to expire the assertion the operation is
/// cancelled (URLSession then throws `.cancelled` right away) and the
/// assertion is ended. No-op on macOS.
func withBackgroundTask<T: Sendable>(
    name: String,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    #if os(iOS)
    let task = Task { try await operation() }
    let assertion = await BackgroundAssertion.begin(name: name) { task.cancel() }
    let result: T
    do {
        result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    } catch {
        await assertion.end()
        throw error
    }
    await assertion.end()
    return result
    #else
    return try await operation()
    #endif
}

#if os(iOS)
/// One `beginBackgroundTask` / `endBackgroundTask` pair. `end()` is
/// idempotent, so the expiration handler and the normal path cannot end
/// the same assertion twice.
@MainActor
private final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(name: String, onExpire: @escaping @Sendable () -> Void) -> BackgroundAssertion {
        let assertion = BackgroundAssertion()
        assertion.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [assertion] in
            onExpire()
            assertion.end()
        }
        return assertion
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif

/// Whether the app is in the background right now (iOS only; macOS: false).
enum AppActivity {
    @MainActor
    static var isBackground: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .background
        #else
        false
        #endif
    }
}
