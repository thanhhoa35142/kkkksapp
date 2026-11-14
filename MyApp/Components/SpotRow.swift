import SwiftUI

/// List row used by Best Now, Saved and the iPad/Mac sidebar (UI_SPEC S1).
/// The score ring is the row's only accent — no icon before the text.
struct SpotRow: View {
    let spot: SpotSummary
    /// "Good until 6 PM" / "Better at 4 PM · 88" (Best Now). nil = no line.
    var timeLine: String? = nil
    /// Meadow for a concrete good hour, secondary for a neutral note.
    var timeLineIsPositive = true
    var badgeDiameter: CGFloat = 44
    /// Best Now's first result uses its own id so layout tests can tell it apart.
    var identifier = "spotRow"

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
        .accessibilityIdentifier(identifier)
        .spotDraggable(spot)
    }

    private var badge: some View {
        ScoreBadge(score: spot.score?.score, capReason: spot.score?.capReason, diameter: badgeDiameter)
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
            if let timeLine {
                Text(timeLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(timeLineIsPositive ? Color.brand : Color.secondary)
                    .monospacedDigit()
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
