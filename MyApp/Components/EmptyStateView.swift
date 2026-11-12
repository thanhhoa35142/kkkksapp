import SwiftUI

/// Thin wrapper over the native `ContentUnavailableView` (iOS 17+) so every
/// feature uses the same empty/error presentation.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    var systemImage: String = "tray"
    var description: LocalizedStringKey?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        }
    }
}

#Preview {
    EmptyStateView(
        title: "No spots here",
        systemImage: "map",
        description: "Try zooming out or panning to a nearby park."
    )
}
