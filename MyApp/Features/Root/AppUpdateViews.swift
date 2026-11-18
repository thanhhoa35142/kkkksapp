import SwiftUI

/// Shown instead of the whole app when the server no longer supports this
/// build (`426 upgrade_required`). Not dismissible on purpose.
struct UpdateRequiredView: View {
    let storeURL: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Update Required", systemImage: "arrow.down.app")
        } description: {
            Text("This version of Pickhour is no longer supported. Update to the latest version to keep finding the best hours for a picnic.")
        } actions: {
            if let storeURL {
                Button("Update") { openURL(storeURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }
}

/// Soft "update available" prompt: a standard alert, once per launch.
struct AppUpdatePrompt: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert("Update Available", isPresented: isPresented) {
            if let url = storeURL {
                Button("Update") { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("A new version of Pickhour is available.")
        }
    }

    private var storeURL: URL? {
        if case .available(let url) = app.appUpdate { return url }
        return nil
    }

    private var isAvailable: Bool {
        if case .available = app.appUpdate { return true }
        return false
    }

    /// Dismissing (either button) drops back to `.none` so it shows once.
    private var isPresented: Binding<Bool> {
        Binding(
            get: { isAvailable },
            set: { newValue in
                if !newValue && isAvailable { app.appUpdate = .none }
            }
        )
    }
}

#Preview("Update required") {
    UpdateRequiredView(storeURL: URL(string: "https://apps.apple.com"))
}
