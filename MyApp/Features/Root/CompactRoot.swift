import SwiftUI

/// iPhone (and folded foldables, iPad Slide Over): four tabs (UI_SPEC §1).
struct CompactRoot: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            BestNowScreen()
                .tabItem { Label("Best Now", systemImage: "list.number") }
                .tag(AppTab.bestNow)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppTab.map)
            SavedScreen()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(AppTab.saved)
            NavigationStack {
                SettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
    }
}
