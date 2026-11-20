import SwiftUI

/// Good-day push: keeps the server's home in step with the chosen place.
/// Runs at launch, on every foreground, and when the place or the first
/// location fix changes; `NudgeStore` decides whether anything is sent
/// (enabled, home changed or a week old, at most once a day).
/// Applied once at the root, so it runs whichever tab is open.
struct NudgeHomeSync: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var foregrounds = 0

    private struct Trigger: Equatable {
        let foregrounds: Int
        let place: Place?
        let enabled: Bool
        let hasFix: Bool
    }

    private var trigger: Trigger {
        Trigger(foregrounds: foregrounds, place: app.place, enabled: app.nudge.isEnabled,
                hasFix: app.location.coordinate != nil)
    }

    func body(content: Content) -> some View {
        content
            .task(id: trigger) { await app.nudge.syncIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { foregrounds += 1 }
            }
    }
}
