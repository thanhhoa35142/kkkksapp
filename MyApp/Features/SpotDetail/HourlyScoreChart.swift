import Accessibility
import Charts
import SwiftUI

/// Hourly scores for one local day (D1). Drag to pick an hour — haptic
/// instead of animation (UI_SPEC §8). Flat colors, no gradient.
///
/// - Every bar keeps its tier color (Meadow / orange / gray); bars other
///   than the active hour are dimmed, so "selected" never means "good".
/// - The active hour gets a rule and an "3 PM · 82" label on the chart
///   itself, so dragging gives feedback even when the big number is
///   scrolled off screen.
/// - Hours capped `dark` / `twilight` sit on a flat neutral band.
struct HourlyScoreChart: View {
    let points: [ForecastPoint]
    let timeZone: TimeZone
    @Binding var selectedHour: Date?
    let activeHour: Date

    @State private var rawSelection: Date?

    private struct Band: Identifiable {
        let start: Date
        let end: Date
        var id: Date { start }
    }

    var body: some View {
        Chart {
            // Bands first so they draw behind the bars.
            ForEach(nightBands) { band in
                RectangleMark(
                    xStart: .value("Hour", band.start),
                    xEnd: .value("Hour", band.end),
                    yStart: .value("Score", 0),
                    yEnd: .value("Score", 100)
                )
                .foregroundStyle(Color.secondary.opacity(0.12))
            }
            ForEach(points, id: \.tsHour) { point in
                BarMark(
                    x: .value("Hour", point.tsHour, unit: .hour),
                    y: .value("Score", point.score)
                )
                .foregroundStyle(color(for: point))
                .cornerRadius(2)
            }
            if let active = activePoint {
                RuleMark(x: .value("Hour", active.tsHour, unit: .hour))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Format.hour(active.tsHour, in: timeZone)) · \(active.score)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.primary)
                    }
            }
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
        // Only user drags set `selectedHour`; switching day resets it to nil
        // and must not tick.
        .sensoryFeedback(.selection, trigger: selectedHour) { _, new in new != nil }
        .frame(height: 120)
        // Room for the hour label above the plot.
        .padding(.top, 18)
        .accessibilityChartDescriptor(self)
    }

    /// The hour the screen shows, if it falls on this day.
    private var activePoint: ForecastPoint? {
        points.first { abs($0.tsHour.timeIntervalSince(activeHour)) < 60 }
    }

    private func color(for point: ForecastPoint) -> Color {
        let isActive = abs(point.tsHour.timeIntervalSince(activeHour)) < 60
        let tierColor = ScoreTier(score: point.score).color
        return isActive ? tierColor : tierColor.opacity(0.45)
    }

    /// Consecutive dark / twilight hours → one band per run, [first, last + 1h).
    private var nightBands: [Band] {
        var bands: [Band] = []
        var runStart: Date?
        var runEnd: Date?
        for point in points.sorted(by: { $0.tsHour < $1.tsHour }) {
            if point.capReason == "dark" || point.capReason == "twilight" {
                if runStart == nil { runStart = point.tsHour }
                runEnd = point.tsHour.addingTimeInterval(3600)
            } else if let start = runStart, let end = runEnd {
                bands.append(Band(start: start, end: end))
                runStart = nil
                runEnd = nil
            }
        }
        if let start = runStart, let end = runEnd {
            bands.append(Band(start: start, end: end))
        }
        return bands
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
