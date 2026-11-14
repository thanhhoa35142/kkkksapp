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
            .onboardingCover(isPresented: Binding(
                get: { !onboardingDone },
                set: { if !$0 { onboardingDone = true } }
            ), fullScreen: isCompact)
            .onChange(of: DeepLinkRouter.shared.pendingSpotID) { _, newValue in
                guard newValue != nil, let id = DeepLinkRouter.shared.consume() else { return }
                app.selectedTab = .map
                app.open(spotID: id, focusMap: true)
            }
            .onOpenURL { url in openLink(url) }
            // Universal links (share page) can arrive as a browsing activity.
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { openLink(url) }
            }
    }

    private func openLink(_ url: URL) {
        guard let id = SpotLink.spotID(from: url) else { return }
        app.track("deep_link_opened", ["host": .string(url.host ?? "")])
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
