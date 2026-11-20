import SwiftUI

/// Weather for one hour: temperature, rain chance and wind as plain columns
/// (no icons — Spot Detail's reason rows below already carry them, and Best
/// Now's hour strip has its own). Accessibility sizes stack them as labelled
/// rows. Shared by Spot Detail (`ForecastPoint.Weather`) and Best Now's
/// "weather near you" (`NearbyWeatherPoint`).
struct HourWeatherRow: View {
    let tempC: Double?
    let feelsLikeC: Double?
    let precipProb: Int?
    let windKmh: Double?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(tempC: Double?, feelsLikeC: Double?, precipProb: Int?, windKmh: Double?) {
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.precipProb = precipProb
        self.windKmh = windKmh
    }

    init(weather: ForecastPoint.Weather) {
        self.init(tempC: weather.tempC, feelsLikeC: weather.feelsLikeC,
                  precipProb: weather.precipProb, windKmh: weather.windKmh)
    }

    init(point: NearbyWeatherPoint) {
        self.init(tempC: point.tempC, feelsLikeC: point.feelsLikeC,
                  precipProb: point.precipProb, windKmh: point.windKmh)
    }

    private struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var items: [Item] {
        var result: [Item] = []
        if let tempC {
            result.append(Item(label: String(localized: "Temperature"), value: Format.temperature(celsius: tempC)))
        }
        if let feelsLikeC, let tempC, abs(feelsLikeC - tempC) >= 2 {
            result.append(Item(label: String(localized: "Feels like"), value: Format.temperature(celsius: feelsLikeC)))
        }
        if let precipProb {
            result.append(Item(label: String(localized: "Rain"), value: "\(precipProb)%"))
        }
        if let windKmh {
            result.append(Item(label: String(localized: "Wind"), value: Format.wind(kmh: windKmh)))
        }
        return result
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ForEach(items) { item in
                LabeledContent(item.label, value: item.value)
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.value)
                            .font(.headline)
                            .monospacedDigit()
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            // "Temperature" in a quarter-width column at
                            // XXXL: shrink a little rather than truncate.
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(item.label): \(item.value)"))
                }
            }
            .padding(.vertical, 2)
        }
    }
}

extension ForecastPoint.Weather {
    /// Something to show in the weather row.
    var hasValues: Bool { tempC != nil || precipProb != nil || windKmh != nil }
}
