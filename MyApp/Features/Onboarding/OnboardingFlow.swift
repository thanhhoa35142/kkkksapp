import SwiftUI

/// S0 · Onboarding — Apple-style Welcome, not a carousel: three pushed
/// steps, ≤ 3 taps to content, no notification prompt, no paywall.
struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Step] = []

    enum Step: Hashable { case place, companions, city }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.place) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .place:
                        PlaceStep(onCity: { path.append(.city) },
                                  onDone: { path.append(.companions) })
                    case .city:
                        CityPickerList { path.append(.companions) }
                    case .companions:
                        CompanionsStep(onDone: finish)
                    }
                }
        }
    }

    private func finish(skipped: Bool) {
        app.track("onboarding_completed", ["skippedWho": .bool(skipped)])
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

/// M2 motion graphic: 24 bars grow once, then the best hour turns Meadow
/// (UI_SPEC §8.1). An illustrative day — labelled as such. Reduce Motion
/// shows the final frame.
private struct DayPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var revealed = false

    private static let values: [Double] = [20, 18, 15, 12, 10, 12, 20, 32, 45, 55, 62, 68,
                                           72, 76, 82, 86, 80, 70, 58, 45, 35, 28, 24, 22]
    private static let bestIndex = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Self.values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == Self.bestIndex && revealed ? Color.brand : Color.secondary.opacity(0.25))
                        .frame(height: grown ? Self.values[index] : 2)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.03),
                                   value: grown)
                }
            }
            .frame(height: 90, alignment: .bottom)
            HStack {
                Text("Example day")
                Spacer()
                if revealed {
                    Text("Best at 3 PM")
                        .foregroundStyle(Color.brand)
                        .transition(.opacity)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example day: the score peaks at 3 PM.")
        .task {
            if reduceMotion {
                grown = true
                revealed = true
                return
            }
            grown = true
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            withAnimation(.easeInOut(duration: 0.25)) { revealed = true }
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

// MARK: - Step 3 · Who

private struct CompanionsStep: View {
    var onDone: (_ skipped: Bool) -> Void

    @Environment(AppState.self) private var app
    @State private var selected: Set<Companion> = []

    var body: some View {
        List {
            Section {
                ForEach(Companion.allCases) { companion in
                    Button {
                        if selected.contains(companion) { selected.remove(companion) }
                        else { selected.insert(companion) }
                    } label: {
                        HStack {
                            Text(companion.title)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if selected.contains(companion) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.brand)
                            }
                        }
                    }
                    .accessibilityAddTraits(selected.contains(companion) ? .isSelected : [])
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who's coming along?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.primary)
                        .textCase(nil)
                    Text("We'll favor spots that suit them.")
                        .font(.body)
                        .textCase(nil)
                }
                .padding(.bottom, 8)
            }
        }
        .groupedList()
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Skip") { onDone(true) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                app.setCompanions(selected)
                onDone(false)
            } label: {
                Text("Start Exploring").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .onAppear { selected = app.companions }
    }
}
