import SwiftUI

/// Spot Detail day selector: 7 columns, each with the day's best score and
/// its hour ("Sat · (87) · 2 PM"). Every plan sees the daily best (spec §15);
/// on Free, days 3+ show a lock and open the paywall instead of the hourly
/// chart. Accessibility sizes switch to one row per day.
struct WeekStrip: View {
    struct Day: Identifiable {
        let date: Date
        let best: ForecastPoint?
        let locked: Bool
        var id: Date { date }
    }

    let days: [Day]
    let timeZone: TimeZone
    let selected: Date
    let onSelect: (Day) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button { onSelect(day) } label: { row(day) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weekStrip.day.\(index)")
                    if day.id != days.last?.id { Divider() }
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button { onSelect(day) } label: { column(day) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("weekStrip.day.\(index)")
                }
            }
        }
    }

    private func column(_ day: Day) -> some View {
        let isSelected = day.date == selected
        return VStack(spacing: 4) {
            Text(Format.dayLabel(day.date, in: timeZone))
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            ScoreBadge(score: day.best?.score, diameter: 32)
            Group {
                if day.locked {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                } else if let best = day.best {
                    Text(Format.hour(best.tsHour, in: timeZone))
                } else {
                    Text(verbatim: " ")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.brandSoft)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label(day)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func row(_ day: Day) -> some View {
        let isSelected = day.date == selected
        return HStack(spacing: 12) {
            ScoreBadge(score: day.best?.score, diameter: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.dayLabel(day.date, in: timeZone))
                    .font(.headline)
                if let best = day.best {
                    Text("Best at \(Format.hour(best.tsHour, in: timeZone))")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if day.locked {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            } else if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.brand)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label(day)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func label(_ day: Day) -> String {
        let name = Format.dayLabel(day.date, in: timeZone)
        guard let best = day.best else { return name }
        let base = String(localized: "\(name), best \(best.score) at \(Format.hour(best.tsHour, in: timeZone))")
        return day.locked ? base + ", " + String(localized: "hourly detail needs Plus") : base
    }

    /// Best hour of each day; ties go to the earlier hour.
    static func days(from dates: [Date], points: (Date) -> [ForecastPoint],
                     locked: (Int) -> Bool) -> [Day] {
        dates.enumerated().map { index, date in
            let best = points(date).reduce(nil as ForecastPoint?) { current, p in
                guard let current else { return p }
                return p.score > current.score ? p : current
            }
            return Day(date: date, best: best, locked: locked(index))
        }
    }
}
