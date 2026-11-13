import SwiftUI

/// One-question exit survey after the paywall closes without a purchase:
/// "What would make Plus worth it?" One tap, no text field, sent as
/// `paywall_feedback {choice, reason}` (no personal data). The feature
/// choices double as votes for the post-launch roadmap.
enum PaywallSurvey {
    enum Choice: String, CaseIterable, Identifiable {
        case shade, offline, weights, sync, price, frequency
        var id: Self { self }

        var title: String {
            switch self {
            case .shade: String(localized: "Shade and sun by hour")
            case .offline: String(localized: "Offline city maps")
            case .weights: String(localized: "Scores tuned for kids or dogs")
            case .sync: String(localized: "Sync across my devices")
            case .price: String(localized: "It costs too much")
            case .frequency: String(localized: "I don't picnic often enough")
            }
        }

        /// Feature votes shuffled per showing (no position bias); the two
        /// "why not" answers stay last.
        static func ordered() -> [Choice] {
            [.shade, .offline, .weights, .sync].shuffled() + [.price, .frequency]
        }
    }

    /// Never on the first close, at most once per 30 days, never for Plus.
    static let minDismissals = 2
    static let cooldown: TimeInterval = 30 * 24 * 3600

    private static let dismissKey = "paywall.dismissCount"
    private static let askedKey = "paywall.surveyAskedAt"

    /// Records a close without purchase; true when the survey should show now.
    static func registerDismissal(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        let count = defaults.integer(forKey: dismissKey) + 1
        defaults.set(count, forKey: dismissKey)
        guard count >= minDismissals else { return false }
        if let last = defaults.object(forKey: askedKey) as? Date, now.timeIntervalSince(last) < cooldown {
            return false
        }
        defaults.set(now, forKey: askedKey)
        return true
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dismissKey)
        defaults.removeObject(forKey: askedKey)
    }
}

extension View {
    /// Attach once at the root, next to the paywall sheet.
    func paywallSurvey() -> some View { modifier(PaywallSurveyModifier()) }
}

private struct PaywallSurveyModifier: ViewModifier {
    @Environment(AppState.self) private var app
    @State private var choices = PaywallSurvey.Choice.ordered()

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "What would make Plus worth it?",
            isPresented: Binding(
                get: { app.survey != nil },
                set: { if !$0 { app.survey = nil } }
            ),
            titleVisibility: .visible,
            presenting: app.survey
        ) { reason in
            ForEach(choices) { choice in
                Button(choice.title) { send(choice.rawValue, reason) }
            }
            Button("Not Now", role: .cancel) { send("dismissed", reason) }
        } message: { _ in
            Text("One tap helps us decide what to build next.")
        }
        .onChange(of: app.survey) { _, newValue in
            if newValue != nil { choices = PaywallSurvey.Choice.ordered() }
        }
    }

    private func send(_ choice: String, _ reason: PaywallReason) {
        app.track("paywall_feedback", ["choice": .string(choice), "reason": .string(reason.rawValue)])
        app.survey = nil
    }
}
