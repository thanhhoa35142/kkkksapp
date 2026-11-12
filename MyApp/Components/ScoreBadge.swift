import SwiftUI

/// Score → display tier. Thresholds are a first pass — tune with design.
enum ScoreTier {
    case great, good, fair, poor

    init(score: Int) {
        switch score {
        case 80...: self = .great
        case 60..<80: self = .good
        case 40..<60: self = .fair
        default: self = .poor
        }
    }
}


struct ScoreBadge: View {
    let score: Int?

    private var tier: ScoreTier? { score.map(ScoreTier.init) }

    private var tint: Color {
        switch tier {
        case .great: return .green
        case .good: return .mint
        case .fair: return .orange
        case .poor: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        if let score {
            Text("\(score)")
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint, in: Capsule())
                .accessibilityLabel("Score \(score) out of 100")
        } else {
            Image(systemName: "minus")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("No score yet")
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        ScoreBadge(score: 92)
        ScoreBadge(score: 65)
        ScoreBadge(score: 45)
        ScoreBadge(score: 12)
        ScoreBadge(score: nil)
    }
    .padding()
}
