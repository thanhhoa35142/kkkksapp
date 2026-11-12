import SwiftUI


struct LoadingRows: View {
    var count: Int = 3
    var height: CGFloat = 56

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: height)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// Convenience modifier for "loading" content — keeps old content visible
/// while refetching, dims it slightly (native `.redacted` behaviour).
extension View {
    func loading(_ isLoading: Bool) -> some View {
        redacted(reason: isLoading ? .placeholder : [])
    }
}

#Preview {
    LoadingRows()
        .padding()
}
