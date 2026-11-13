import SwiftData
import SwiftUI

/// Heart toggle for a spot (toolbar / swipe action). Free plan caps saved
/// spots at 10 — over the cap it opens the paywall instead.
struct SaveButton: View {
    let spot: SpotSummary

    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var favorites: [FavoriteSpot]

    private var isSaved: Bool { favorites.contains { $0.spotID == spot.id } }

    var body: some View {
        Button {
            let added = !isSaved
            if Favorites.toggle(spot, existing: favorites, isPlus: app.isPlus, context: context) {
                app.track(added ? "spot_saved" : "spot_unsaved")
            } else {
                app.paywall = .saved
            }
        } label: {
            Label(isSaved ? "Unsave" : "Save", systemImage: isSaved ? "heart.fill" : "heart")
        }
        .symbolEffect(.bounce, value: isSaved)
        .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
    }
}
