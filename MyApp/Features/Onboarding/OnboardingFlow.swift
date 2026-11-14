import SwiftUI

/// S0 · Onboarding — Apple-style Welcome, not a carousel: two pushed
/// steps (Welcome → Where), at most 2 taps to content, no notification
/// prompt, no paywall. Choosing a place finishes onboarding.
///
/// There is no "Who's coming?" step: the backend doesn't rank by
/// companions yet, so asking would promise something the app doesn't do.
/// `Companion` / `AppState.companions` stay for when it does.
struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    enum Step: Hashable { case place, city }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.place) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .place:
                        PlaceStep(onCity: { path.append(.city) },
                                  onDone: { finish(place: "location") })
                    case .city:
                        CityPickerList { finish(place: "city") }
                    }
                }
        }
    }

    /// `place`: "location" | "city" — how the first place was chosen.
    private func finish(place: String) {
        app.track("onboarding_completed", ["place": .string(place)])
        dismiss()
    }
}

// MARK: - Step 1 · Welcome

private struct WelcomeStep: View {
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Welcome to Pickhour")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                DayPreview()
                VStack(alignment: .leading, spacing: 20) {
                    Feature(symbol: "gauge.medium", title: "Best spot, right now",
                            detail: "Every park, beach and picnic area gets an hourly score from 0 to 100.")
                    Feature(symbol: "text.bubble", title: "Why it's good",
                            detail: "Weather, crowds and toilets nearby, in plain words.")
                    Feature(symbol: "calendar", title: "Plan the weekend",
                            detail: "See which hour works best, up to a week ahead.")
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Map data © OpenStreetMap contributors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .background(.bar)
        }
    }

    private struct Feature: View {
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.brand)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// M2 motion graphic: the bars of an example day grow once, then the best
/// hour turns Meadow and the app's own `ScoreBadge` counts up to its score —
/// the same ring the user meets on every row (UI_SPEC §8.1). One shot,
/// 1.0 s total, chained with `withAnimation` completions (no timed sleep).
/// Labelled as an example. Reduce Motion shows the final frame.
private struct DayPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var revealed = false

    private static let values: [Double] = [20, 18, 15, 12, 10, 12, 20, 32, 45, 55, 62, 68,
                                           72, 76, 82, 86, 80, 70, 58, 45, 35, 28, 24, 22]
    private static let bestIndex = 15
    private static var bestScore: Int { Int(values[bestIndex]) }

    private static var bestHourLabel: String {
        let hour = Calendar.current.date(bySettingHour: bestIndex, minute: 0, second: 0, of: .now) ?? .now
        return Format.hour(hour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 16) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Self.values.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == Self.bestIndex && revealed ? Color.brand : Color.secondary.opacity(0.25))
                            .frame(height: grown ? Self.values[index] : 2)
                    }
                }
                .frame(height: 90, alignment: .bottom)
                ScoreBadge(score: revealed ? Self.bestScore : 0, diameter: 56,
                           animatesChanges: true, motionDuration: 0.5, maxTypeScale: 1.2)
                    .opacity(grown ? 1 : 0)
            }
            HStack {
                Text("Example day")
                Spacer()
                if revealed {
                    Text("Best at \(Self.bestHourLabel)")
                        .foregroundStyle(Color.brand)
                        .transition(.opacity)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Example day: the score peaks at \(Self.bestScore) at \(Self.bestHourLabel)."))
        .task {
            guard !grown else { return }
            if reduceMotion {
                grown = true
                revealed = true
                return
            }
            withAnimation(.easeOut(duration: 0.5)) {
                grown = true
            } completion: {
                withAnimation(.easeInOut(duration: 0.5)) { revealed = true }
            }
        }
    }
}

// MARK: - Step 2 · Where

private struct PlaceStep: View {
    var onCity: () -> Void
    var onDone: () -> Void

    @Environment(AppState.self) private var app
    @State private var asking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where do you picnic?")
                    .font(.largeTitle.bold())
                Text("We use your location only while the app is open, and never store it.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task {
                        asking = true
                        _ = await app.location.requestAuthorization()
                        asking = false
                        if app.location.isAuthorized {
                            app.setPlace(.currentLocation)
                            onDone()
                        } else {
                            onCity()
                        }
                    }
                } label: {
                    Text("Use My Location").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(asking || app.location.isDenied)

                Button(action: onCity) {
                    Text("Choose a City").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .inlineTitle()
    }
}
