import SwiftUI

/// Picks the layout from the window's size class / width — never from the
/// device model (UI_SPEC §10.2). Compact = tabs; regular = Explore split view.
struct RootView: View {
    @Environment(AppState.self) private var app
    @AppStorage("onboardingDone") private var onboardingDone = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        @Bindable var app = app
        layout
            .sheet(item: $app.paywall, onDismiss: { app.paywallDidDismiss() }) { reason in
                PaywallSheet(reason: reason)
            }
            .paywallSurvey()
            .modifier(WidgetPlanSync())
            .modifier(PlanRouting())
            .modifier(NudgeHomeSync())
            .onboardingCover(isPresented: Binding(
                get: { !onboardingDone },
                set: { if !$0 { onboardingDone = true } }
            ), fullScreen: isCompact)
            .onChange(of: DeepLinkRouter.shared.pendingSpotID) { _, newValue in
                guard newValue != nil, let id = DeepLinkRouter.shared.consume() else { return }
                // Good-day push: the best window's hour, if still usable.
                if let raw = DeepLinkRouter.shared.consumeHour(),
                   let hour = PlanLink.usableHour(raw, isPlus: app.isPlus) {
                    app.detailFocus = AppState.DetailFocus(spotID: id, hour: hour)
                    app.select(when: .at(hour))
                }
                app.selectedTab = .map
                app.open(spotID: id, focusMap: true)
            }
            .onOpenURL { url in openLink(url) }
            // Universal links (share page) can arrive as a browsing activity.
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { openLink(url) }
            }
    }

    /// Plan links open the plan sheet. Spot links, optionally at an hour (`?at=`, `PlanLink`) and tagged
    /// `src=widget` by the widget. An hour that is past, too far out or
    /// (Free) after tomorrow is ignored: the spot opens at the current "When".
    private func openLink(_ url: URL) {
        // Plan links (`/p/<token>`, `pickhour://plan/<token>`) before spot
        // links; the token's shape is checked before any request.
        if let token = PlanShareLink.token(from: url) {
            app.track("shared_plan_link_opened")
            app.planSheet = .shared(token: token)
            return
        }
        let id = SpotLink.spotID(from: url)
        let fromWidget = PlanLink.source(of: url) == PlanLink.widgetSource
        if fromWidget {
            app.track("widget_opened", ["hasSpot": .bool(id != nil)])
        }
        guard let id else { return }
        app.track("deep_link_opened", ["host": .string(url.host ?? "")])
        if let raw = PlanLink.hour(in: url) {
            let hour = PlanLink.usableHour(raw, isPlus: app.isPlus)
            if let hour {
                // Before the selection, so the detail finds it when it opens.
                app.detailFocus = AppState.DetailFocus(spotID: id, hour: hour)
                app.select(when: .at(hour))
            }
            if !fromWidget {
                app.track("plan_link_opened", ["usable": .bool(hour != nil)])
            }
        }
        DeepLinkRouter.shared.handle(spotID: id)
    }

    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if sizeClass == .compact {
            CompactRoot()
        } else {
            RegularRoot()
        }
        #else
        RegularRoot()
        #endif
    }
}

private extension View {
    /// Full screen on iPhone; centered form sheet on iPad and Mac.
    @ViewBuilder
    func onboardingCover(isPresented: Binding<Bool>, fullScreen: Bool) -> some View {
        #if os(iOS)
        if fullScreen {
            fullScreenCover(isPresented: isPresented) { OnboardingFlow() }
        } else {
            sheet(isPresented: isPresented) {
                OnboardingFlow()
                    .interactiveDismissDisabled()
            }
        }
        #else
        sheet(isPresented: isPresented) {
            OnboardingFlow()
                .frame(width: 520, height: 640)
                .interactiveDismissDisabled()
        }
        #endif
    }
}
