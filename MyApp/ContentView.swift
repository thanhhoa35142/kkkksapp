import SwiftUI

/// App root — layout selection lives in RootView. A build the server no
/// longer supports sees only the update screen (no sheets, no tabs).
struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if case .required(let storeURL) = app.appUpdate {
            UpdateRequiredView(storeURL: storeURL)
        } else {
            RootView()
                .modifier(AppUpdatePrompt())
        }
    }
}
