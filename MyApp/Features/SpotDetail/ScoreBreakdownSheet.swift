import SwiftUI

/// S7 · "Why 82?" — what the score is made of, its cap and confidence,
/// plus a one-tap "is this right?" (POST /v1/scores/feedback).
struct ScoreBreakdownSheet: View {
    let spotID: UUID
    let point: ForecastPoint
    let timeZone: TimeZone

    @Environment(\.dismiss) private var dismiss
    @State private var sentVerdict: Int?

    private struct Row: Identifiable {
        let id: String
        let title: String
        let weight: Int
        let value: Int?
    }

    /// Weights from the scoring model (requirements §8); missing data is
    /// shown as "—", never as 0.
    private var rows: [Row] {
        let c = point.components
        return [
            Row(id: "weather", title: String(localized: "Weather"), weight: 40, value: c.weather),
            Row(id: "crowd", title: String(localized: "Crowd"), weight: 25, value: c.crowd),
            Row(id: "amenity", title: String(localized: "Amenities"), weight: 20, value: c.amenity),
            Row(id: "shade", title: String(localized: "Shade"), weight: 10, value: c.shade),
            Row(id: "fresh", title: String(localized: "Freshness"), weight: 5, value: c.fresh),
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.title)
                                Spacer()
                                Text(row.value.map { "\($0)" } ?? "—")
                                    .monospacedDigit()
                                    .foregroundStyle(row.value == nil ? .secondary : .primary)
                            }
                            Gauge(value: Double(row.value ?? 0), in: 0...100) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .tint(row.value == nil ? Color.secondary.opacity(0.3) : Color.brand)
                            Text("\(row.weight)% of the score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(Format.dayHour(point.tsHour, in: timeZone))
                } footer: {
                    if rows.contains(where: { $0.value == nil }) {
                        Text("“—” means no data; the other parts count for more.")
                    }
                }

                if let cap = point.capReason {
                    Section {
                        Label(capText(cap), systemImage: CapStyle.symbol(cap) ?? "exclamationmark.triangle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                Section {
                    Text(Format.confidence(point.confidence))
                        .font(.headline)
                    Text("Crowd levels are an estimate, not live data.")
                        .foregroundStyle(.secondary)
                }

                Section("Is this score right?") {
                    if sentVerdict != nil {
                        Text("Thanks — this helps tune the score.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            verdictButton(-1, "Too high", "hand.thumbsdown")
                            verdictButton(0, "About right", "equal")
                            verdictButton(1, "Too low", "hand.thumbsup")
                        }
                        .buttonStyle(.bordered)
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Why \(point.score)?")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: sentVerdict)
        }
        .presentationDetents([.medium, .large])
    }

    /// -1: score feels too high, +1: too low (API verdict semantics).
    private func verdictButton(_ verdict: Int, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button {
            sentVerdict = verdict
            Task {
                _ = try? await AppConfig.apiClient.submitScoreFeedback(
                    spotID: spotID, deviceID: DeviceIdentity.deviceID,
                    tsHour: point.tsHour, verdict: verdict)
            }
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
    }

    private func capText(_ cap: String) -> String {
        switch cap {
        case "rain": String(localized: "Capped because rain is likely.")
        case "heat": String(localized: "Capped because of extreme heat.")
        case "cold": String(localized: "Capped because it's freezing.")
        case "dark": String(localized: "Capped because it's dark at this hour.")
        case "twilight": String(localized: "Capped because the sun is setting or rising.")
        default: String(localized: "Capped by the weather.")
        }
    }
}
