import SwiftUI

/// Score ring with the number inside — the one visual accent of a row
/// (UI_SPEC §2). Color by tier, fill by value. The number is shown unless
/// the caller already prints it next to the ring (Spot Detail), so the score
/// never depends on color alone and is never printed twice.
///
/// Motion (UI_SPEC §8): lists pass `animatesChanges: false` (the default) —
/// the list cross-fades once instead of N rings rolling. Single-value
/// contexts opt in; ring and number then share one curve. Reduce Motion:
/// the number cross-fades and the ring jumps.
struct ScoreBadge: View {
    let score: Int?
    var capReason: String? = nil
    var diameter: CGFloat = 44
    /// false = ring only (the number is shown elsewhere in the same row).
    var showsNumber = true
    /// Animate value changes (ring + number, one curve).
    var animatesChanges = false
    /// Duration of that one curve; 0.25 s for UI, ≤ 0.5 s for M3 / onboarding.
    var motionDuration: Double = 0.25
    /// Upper bound for Dynamic Type growth (tight layouts like the week strip).
    var maxTypeScale: CGFloat = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Grows the badge with Dynamic Type; clamped so rows never break.
    @ScaledMetric(relativeTo: .subheadline) private var typeScale: CGFloat = 1

    private var tier: ScoreTier? { score.map(ScoreTier.init) }
    private var size: CGFloat { diameter * min(max(typeScale, 1), maxTypeScale) }
    private var lineWidth: CGFloat { max(3, size / 11) }
    private var numberFont: Font { .system(size: size * 0.36, weight: .semibold, design: .rounded) }

    private var animation: Animation? {
        guard animatesChanges else { return nil }
        return .smooth(duration: motionDuration)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            if let score, let tier {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(tier.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : animation, value: score)
                if showsNumber {
                    Text(score, format: .number)
                        .font(numberFont)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.horizontal, lineWidth)
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(score)))
                        .animation(animation, value: score)
                }
            } else if showsNumber {
                Text(verbatim: "–")
                    .font(numberFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let symbol = CapStyle.symbol(capReason) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.26))
                    .foregroundStyle(.orange)
                    .offset(x: 4, y: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let score, let tier else { return String(localized: "No score yet") }
        return String(localized: "Score \(score), \(tier.label)")
    }
}

#Preview {
    HStack(spacing: 12) {
        ScoreBadge(score: 92)
        ScoreBadge(score: 65)
        ScoreBadge(score: 45, capReason: "rain")
        ScoreBadge(score: 12)
        ScoreBadge(score: nil)
        ScoreBadge(score: 82, diameter: 56, showsNumber: false)
    }
    .padding()
}
