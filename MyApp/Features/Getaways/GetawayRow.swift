import SwiftUI

/// One city in Getaways: flag and name, when and where to go in the city's
/// own time, the city's weather quality (secondary text, never a ring), the
/// top spot with its total score, why, and how far it is.
struct GetawayRow: View {
    let city: Getaway
    /// From the device's last location to the city's center; nil = unknown.
    var distanceMeters: Double?
    /// The user's own city ("Your City").
    var isHome = false

    var body: some View {
        // Three groups — when, the city's weather, the spot — with more
        // room between groups than within one.
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text(windowLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if GetawayRules.showsLocalTimeCaption(city) {
                    Text("local time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            weatherLine
            VStack(alignment: .leading, spacing: 4) {
                if let spot = city.topSpot {
                    spotLine(spot)
                }
                if let reasons = reasonsLine {
                    Text(reasons)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let meta = metaLine {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("getawayRow")
    }

    /// Width of the weather icon and the spot's ring, so the two texts align.
    private static let leadingColumn: CGFloat = 32

    private var title: String {
        let flag = GetawayRules.flag(for: city.country)
        return flag.isEmpty ? city.name : "\(flag) \(city.name)"
    }

    /// "Sun 1 PM–5 PM", in the city's time zone.
    private var windowLine: String {
        GetawayRules.windowLabel(city)
    }

    /// The city's weather quality as secondary text: "Weather 86" for one
    /// day, "Weather Sat 71 · Sun 86" for a range. It is not a total score,
    /// so it gets no ring.
    private var weatherLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.sun")
                .frame(width: Self.leadingColumn)
                .accessibilityHidden(true)
            if let days = GetawayRules.dayScoresLine(city) {
                Text("Weather \(days)")
            } else {
                Text("Weather \(city.weatherScore)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// The best spot with its total score: the same number its detail shows.
    private func spotLine(_ spot: GetawayTopSpot) -> some View {
        HStack(spacing: 8) {
            if let score = spot.score {
                ScoreBadge(score: score, diameter: Self.leadingColumn)
            }
            Text(spot.name)
                .font(.subheadline)
                .lineLimit(2)
        }
    }

    /// Up to 2 reasons this build can phrase.
    private var reasonsLine: String? {
        let texts = city.knownReasons.prefix(2).map { ReasonLocalizer.text(for: $0) }
        return texts.isEmpty ? nil : texts.joined(separator: " · ")
    }

    /// "Your City", or the distance from the user.
    private var metaLine: String? {
        if isHome { return String(localized: "Your City") }
        guard let distanceMeters else { return nil }
        return Format.distance(meters: distanceMeters)
    }
}

/// Best Now's footer row: "This weekend looks better in Lisbon". Tapping
/// opens Getaways; showing it uses up this week's hint.
struct GetawaysHintSection: View {
    let city: Getaway

    @Environment(AppState.self) private var app

    var body: some View {
        Section {
            Button {
                app.getawaysSource = .hint
            } label: {
                Label("This weekend looks better in \(city.name)", systemImage: "sun.max")
                    .font(.subheadline)
            }
            .tint(.primary)
            .onAppear { GetawayRules.markHintShown() }
            .accessibilityIdentifier("getawaysHint")
        }
    }
}
