import SwiftUI

/// Score ring with the number inside — the one visual accent of a row
/// (UI_SPEC §2). Color by tier, fill by value, number always shown, so the
/// score never depends on color alone.
struct ScoreBadge: View {
    let score: Int?
    var capReason: String? = nil
    var diameter: CGFloat = 44

    private var tier: ScoreTier? { score.map(ScoreTier.init) }
    private var lineWidth: CGFloat { max(3, diameter / 11) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            if let score, let tier {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(tier.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: score)
                Text(score, format: .number)
                    .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(.snappy(duration: 0.25), value: score)
            } else {
                Text(verbatim: "–")
                    .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottomTrailing) {
            if let symbol = CapStyle.symbol(capReason) {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.26))
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
    }
    .padding()
}
