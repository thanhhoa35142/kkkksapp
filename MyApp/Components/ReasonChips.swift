import SwiftUI


struct ReasonChips: View {
    let reasons: [Reason]

    var body: some View {
        // API guarantees ≤3 reasons — a plain HStack is enough, no flow layout needed.
        HStack(spacing: 6) {
            ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                Text(ReasonLocalizer.text(for: reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

#Preview {
    ReasonChips(reasons: [
        Reason(code: "weather.clear", params: ["temp": .number(21)]),
        Reason(code: "crowd.low", params: nil),
        Reason(code: "cap.rain", params: nil),
    ])
    .padding()
}
