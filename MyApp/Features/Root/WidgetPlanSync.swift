import SwiftData
import SwiftUI
import WidgetKit

/// Hands upcoming picnic plans and the Free / Plus limit to the widget
/// (App Group, `WidgetBridge`) and reloads it when either changes.
/// Applied once at the root, so it runs whichever tab is open.
struct WidgetPlanSync: ViewModifier {
    @Environment(AppState.self) private var app
    @Query(sort: \PicnicPlan.start) private var plans: [PicnicPlan]

    private var upcoming: [PlanSnapshot] {
        let now = Date.now
        return plans.filter { !$0.isEnded(now: now) }.map(\.snapshot)
    }

    func body(content: Content) -> some View {
        content
            .task(id: upcoming) {
                if WidgetBridge.savePlans(upcoming) {
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.bestNowKind)
                }
            }
            .task(id: app.isPlus) {
                app.syncWidgetEntitlement()
            }
    }
}
