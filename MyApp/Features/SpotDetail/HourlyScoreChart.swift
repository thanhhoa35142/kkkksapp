import Accessibility
import Charts
import SwiftUI

/// Hourly scores for one local day (D1). Drag to pick an hour — haptic
/// instead of animation (UI_SPEC §8). Flat colors, no gradient.
struct HourlyScoreChart: View {
    let points: [ForecastPoint]
    let timeZone: TimeZone
    @Binding var selectedHour: Date?
    let activeHour: Date

    @State private var rawSelection: Date?

    var body: some View {
        Chart(points, id: \.tsHour) { point in
            BarMark(
                x: .value("Hour", point.tsHour, unit: .hour),
                y: .value("Score", point.score)
            )
            .foregroundStyle(color(for: point))
            .cornerRadius(2)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Format.hour(date, in: timeZone))
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, newValue in
            guard let newValue else { return }
            let snapped = snap(newValue)
            if snapped != selectedHour { selectedHour = snapped }
        }
        .sensoryFeedback(.selection, trigger: selectedHour)
        .frame(height: 120)
        .accessibilityChartDescriptor(self)
    }

    private func color(for point: ForecastPoint) -> Color {
        let isActive = abs(point.tsHour.timeIntervalSince(activeHour)) < 60
        let tierColor = ScoreTier(score: point.score).color
        return isActive ? Color.brand : tierColor.opacity(0.35)
    }

    /// Nearest whole hour present in the data.
    private func snap(_ date: Date) -> Date? {
        points.min { abs($0.tsHour.timeIntervalSince(date)) < abs($1.tsHour.timeIntervalSince(date)) }?.tsHour
    }
}

extension HourlyScoreChart: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Hour"),
            categoryOrder: points.map { Format.hour($0.tsHour, in: timeZone) })
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Score"), range: 0...100, gridlinePositions: [0, 50, 100]
        ) { value in "\(Int(value))" }
        let series = AXDataSeriesDescriptor(
            name: String(localized: "Picnic score"), isContinuous: false,
            dataPoints: points.map {
                AXDataPoint(x: Format.hour($0.tsHour, in: timeZone), y: Double($0.score))
            })
        return AXChartDescriptor(title: String(localized: "Hourly picnic score"), summary: nil,
                                 xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
