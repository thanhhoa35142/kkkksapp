import SwiftUI

/// M5 · success confirmation where the user lands after sending something
/// (report, crowd level). A checkmark that bounces once — an SF Symbol
/// effect available since iOS 17 / macOS 14. No toast, no confetti.
/// Reduce Motion: the mark simply appears.
struct ConfirmationMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trigger = 0

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.brand)
            .symbolEffect(.bounce, value: trigger)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                // Let a closing sheet get out of the way first.
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                trigger += 1
            }
    }
}
