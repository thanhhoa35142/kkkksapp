import SwiftUI

/// List row used by Best Now, Saved and the iPad/Mac sidebar (UI_SPEC S1).
/// The score ring is the row's only accent — no icon before the text.
struct SpotRow: View {
    let spot: SpotSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    badge
                    text
                }
            } else {
                HStack(spacing: 12) {
                    badge
                    text
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .spotDraggable(spot)
    }

    private var badge: some View {
        ScoreBadge(score: spot.score?.score, capReason: spot.score?.capReason)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spot.displayName)
                .font(.headline)
                .lineLimit(2)
            Text(spot.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let line = spot.reasonLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

extension View {
    /// Drag a spot into Maps, Messages, Notes, Mail… as its Apple Maps link
    /// (iPad split view / Slide Over, Mac windows). No-op without coordinates.
    @ViewBuilder
    func spotDraggable(_ spot: SpotSummary) -> some View {
        if let url = spot.mapsURL {
            draggable(url) {
                Label(spot.displayName, systemImage: KindStyle.symbol(spot.kind))
                    .font(.headline)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } else {
            self
        }
    }
}
