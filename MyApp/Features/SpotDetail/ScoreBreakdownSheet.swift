import Charts
import SwiftUI

/// S7 · "Why 82?" — what the score is made of, its cap and confidence,
/// plus a one-tap "is this right?" (POST /v1/scores/feedback).
///
/// One stacked bar shows each part's contribution (weight × value), so
/// Weather at 40 % visibly matters more than Freshness at 5 %. Plain rows
/// below give the value and the effective weight. Parts without data are
/// left out; the server then spreads their weight over the others
/// (backend `scoring.Score`: Σ wᵢ·vᵢ / Σ wᵢ over present parts), and the
/// rows show those re-normalized weights so the numbers add up.
struct ScoreBreakdownSheet: View {
    let spotID: UUID
    let point: ForecastPoint
    let timeZone: TimeZone

    @Environment(\.dismiss) private var dismiss
    @State private var sentVerdict: Int?

    private struct Part: Identifiable {
        let id: String
        let title: String
        /// Nominal weight from the scoring model (requirements §8).
        let weight: Double
        let value: Int?
        let color: Color
        /// Shown in the footer when missing (Shade isn't shipped yet, so it is silent).
        let reportsMissing: Bool
    }

    private struct Contribution: Identifiable {
        let part: Part
        let share: Double   // effective weight, 0…1
        let points: Double  // share × value
        var id: String { part.id }
    }

    /// Meadow plus neutral tints — no rainbow.
    private var parts: [Part] {
        let c = point.components
        return [
            Part(id: "weather", title: String(localized: "Weather"), weight: 40, value: c.weather,
                 color: .brand, reportsMissing: true),
            Part(id: "crowd", title: String(localized: "Crowd"), weight: 25, value: c.crowd,
                 color: Color.brand.opacity(0.55), reportsMissing: true),
            Part(id: "amenity", title: String(localized: "Amenities"), weight: 20, value: c.amenity,
                 color: Color.secondary.opacity(0.55), reportsMissing: true),
            Part(id: "shade", title: String(localized: "Shade"), weight: 10, value: c.shade,
                 color: Color.secondary.opacity(0.4), reportsMissing: false),
            Part(id: "fresh", title: String(localized: "Freshness"), weight: 5, value: c.fresh,
                 color: Color.secondary.opacity(0.25), reportsMissing: true),
        ]
    }

    private var contributions: [Contribution] {
        let present = parts.filter { $0.value != nil }
        let total = present.reduce(0.0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return present.map { part in
            let share = part.weight / total
            return Contribution(part: part, share: share, points: share * Double(part.value ?? 0))
        }
    }

    /// Sum before any cap (rounds to the score when uncapped).
    private var uncapped: Int {
        Int(contributions.reduce(0.0) { $0 + $1.points }.rounded())
    }

    private var missingTitles: [String] {
        parts.filter { $0.value == nil && $0.reportsMissing }.map(\.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !contributions.isEmpty {
                        contributionBar
                            .padding(.vertical, 6)
                    }
                    ForEach(contributions) { item in
                        row(item)
                    }
                } header: {
                    Text(Format.dayHour(point.tsHour, in: timeZone))
                } footer: {
                    if !missingTitles.isEmpty {
                        Text("No \(missingTitles.formatted(.list(type: .and))) data for this hour, so the other parts count for more.")
                    }
                }

                if let cap = point.capReason {
                    Section {
                        Label(capText(cap), systemImage: CapStyle.symbol(cap) ?? "exclamationmark.triangle")
                            .symbolRenderingMode(.hierarchical)
                    } footer: {
                        if uncapped > point.score {
                            Text("Without the cap the parts add up to \(uncapped).")
                        }
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
                        Text("Thanks. This helps tune the score.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            verdictButton(-1, "Too high")
                            verdictButton(0, "About right")
                            verdictButton(1, "Too low")
                        }
                        .buttonStyle(.bordered)
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

    /// One flat stacked bar on a 0–100 track; the rows carry the numbers,
    /// so VoiceOver skips the bar.
    private var contributionBar: some View {
        let used = contributions.reduce(0.0) { $0 + $1.points }
        return Chart {
            ForEach(contributions) { item in
                BarMark(x: .value("Points", item.points), y: .value("Score", "score"))
                    .foregroundStyle(item.part.color)
            }
            if used < 100 {
                BarMark(x: .value("Points", 100 - used), y: .value("Score", "score"))
                    .foregroundStyle(Color.secondary.opacity(0.1))
            }
        }
        .chartXScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func row(_ item: Contribution) -> some View {
        let value = item.part.value ?? 0
        let percent = Int((item.share * 100).rounded())
        let points = Int(item.points.rounded())
        return HStack(spacing: 10) {
            Circle()
                .fill(item.part.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.part.title)
                Text("\(percent)% of the score · adds \(points)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(value, format: .number)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(item.part.title): \(value) out of 100, \(percent)% of the score, adds \(points) points"))
    }

    /// -1: score feels too high, +1: too low (API verdict semantics).
    private func verdictButton(_ verdict: Int, _ title: LocalizedStringKey) -> some View {
        Button {
            sentVerdict = verdict
            Task {
                _ = try? await AppConfig.apiClient.submitScoreFeedback(
                    spotID: spotID, deviceID: DeviceIdentity.deviceID,
                    tsHour: point.tsHour, verdict: verdict)
            }
        } label: {
            Text(title)
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
