import SwiftUI
import WidgetKit

// D7 · "Best Now" widget — the top spots around the place chosen in the app,
// for the current hour. Reads the place from the App Group (WidgetBridge) and
// calls `GET /v1/recommendations` itself. After dark it shows tomorrow
// morning instead of a row of capped 10s.

@main
struct PickhourWidgetBundle: WidgetBundle {
    var body: some Widget {
        BestNowWidget()
    }
}

struct BestNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.bestNowKind, provider: BestNowProvider()) { entry in
            BestNowWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Best Now")
        .description("The best picnic spots near your place, right now.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

// MARK: - Data

struct WidgetSpot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let score: Int?
    let distanceM: Double
}

struct BestNowEntry: TimelineEntry {
    enum State: Equatable {
        case spots([WidgetSpot])
        case noPlace       // app never chose a place
        case empty         // no spots around the place
        case failed
    }

    let date: Date
    let placeName: String
    /// Hour the scores are for; differs from `date` after dark ("Tomorrow 10 AM").
    let hour: Date
    let isNextMorning: Bool
    let state: State
    let usesMetric: Bool

    static let placeholder = BestNowEntry(
        date: .now, placeName: "Amsterdam", hour: .now, isNextMorning: false,
        state: .spots([
            WidgetSpot(id: UUID(), name: "Vondelpark", score: 86, distanceM: 1200),
            WidgetSpot(id: UUID(), name: "Westerpark", score: 78, distanceM: 2600),
            WidgetSpot(id: UUID(), name: "Amstelpark", score: 71, distanceM: 5400),
        ]),
        usesMetric: true)
}

struct BestNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> BestNowEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (BestNowEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BestNowEntry>) -> Void) {
        Task {
            let entry = await load()
            // Scores are hourly: refresh just after the next hour; retry
            // sooner after a failure.
            let calendar = Calendar.current
            let nextHour = calendar.dateInterval(of: .hour, for: .now)?.end ?? .now.addingTimeInterval(3600)
            let refresh = entry.state == .failed ? Date.now.addingTimeInterval(15 * 60) : nextHour.addingTimeInterval(5 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func load(now: Date = .now) async -> BestNowEntry {
        guard let snapshot = WidgetBridge.load() else {
            return BestNowEntry(date: now, placeName: "", hour: now, isNextMorning: false,
                                state: .noPlace, usesMetric: true)
        }
        do {
            var hour = now
            var nextMorning = false
            var result = try await WidgetAPI.recommendations(snapshot, when: nil)
            if !result.items.isEmpty, result.items.allSatisfy({ $0.score?.capReason == "dark" }) {
                hour = Self.nextMorning(after: now)
                nextMorning = true
                result = try await WidgetAPI.recommendations(snapshot, when: hour)
            }
            let spots = result.items.map {
                WidgetSpot(id: $0.id, name: $0.displayName, score: $0.score?.score, distanceM: $0.distanceM)
            }
            return BestNowEntry(date: now, placeName: snapshot.placeName, hour: hour, isNextMorning: nextMorning,
                                state: spots.isEmpty ? .empty : .spots(spots), usesMetric: snapshot.usesMetric)
        } catch {
            return BestNowEntry(date: now, placeName: snapshot.placeName, hour: now, isNextMorning: false,
                                state: .failed, usesMetric: snapshot.usesMetric)
        }
    }

    /// 10:00 today if it's still before 10, else 10:00 tomorrow.
    static func nextMorning(after now: Date, calendar: Calendar = .current) -> Date {
        let today10 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        return now < today10 ? today10 : (calendar.date(byAdding: .day, value: 1, to: today10) ?? today10)
    }
}

/// Minimal client — the widget doesn't link the app's APIClient.
enum WidgetAPI {
    struct Response: Decodable {
        struct Item: Decodable {
            struct Score: Decodable {
                let score: Int
                let capReason: String?
            }
            let id: UUID
            let kind: String
            let name: String?
            let names: [String: String]?
            let city: String?
            let distanceM: Double
            let score: Score?

            /// Localized OSM name, else the default name, else "Park · City".
            var displayName: String {
                let language = Locale.current.language.languageCode?.identifier ?? "en"
                if let local = names?[language], !local.isEmpty { return local }
                if let name, !name.isEmpty { return name }
                let kindLabel: String = switch kind {
                case "park": String(localized: "Park")
                case "beach": String(localized: "Beach")
                case "site": String(localized: "Picnic area")
                case "table": String(localized: "Picnic table")
                default: String(localized: "Spot")
                }
                return [kindLabel, city].compactMap { $0 }.joined(separator: " · ")
            }
        }
        let items: [Item]
    }

    private struct Envelope: Decodable { let data: Response }

    static func recommendations(_ snapshot: WidgetBridge.Snapshot, when: Date?) async throws -> Response {
        guard var components = URLComponents(string: snapshot.apiBaseURL) else { throw URLError(.badURL) }
        components.path = "/v1/recommendations"
        var query = [
            URLQueryItem(name: "lat", value: String(snapshot.latitude)),
            URLQueryItem(name: "lon", value: String(snapshot.longitude)),
            URLQueryItem(name: "radius", value: "10000"),
            URLQueryItem(name: "limit", value: "3"),
        ]
        if let when { query.append(URLQueryItem(name: "when", value: ISO8601DateFormatter().string(from: when))) }
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("pickhour-widget", forHTTPHeaderField: "X-Client")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ","), forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
}

// MARK: - Views

struct BestNowWidgetView: View {
    let entry: BestNowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        #endif
        case .systemMedium: medium
        default: small
        }
    }

    private var spots: [WidgetSpot] {
        if case .spots(let s) = entry.state { return s }
        return []
    }

    private var hourLabel: String {
        if entry.isNextMorning {
            let hour = entry.hour.formatted(.dateTime.hour())
            return Calendar.current.isDateInToday(entry.hour)
                ? String(localized: "This morning \(hour)")
                : String(localized: "Tomorrow \(hour)")
        }
        return String(localized: "Now")
    }

    // Small: the one best spot.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let top = spots.first {
                WidgetScoreRing(score: top.score, diameter: 40)
                Text(top.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            } else {
                message
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(spots.first.map { WidgetBridge.spotURL($0.id) })
    }

    // Medium: top three, each row tappable.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if spots.isEmpty {
                Spacer(minLength: 0)
                message
                Spacer(minLength: 0)
            } else {
                ForEach(spots.prefix(3)) { spot in
                    Link(destination: WidgetBridge.spotURL(spot.id)) {
                        HStack(spacing: 10) {
                            WidgetScoreRing(score: spot.score, diameter: 30)
                            Text(spot.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(distance(spot.distanceM))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(entry.placeName.isEmpty ? String(localized: "Pickhour") : entry.placeName)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(hourLabel)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var message: some View {
        switch entry.state {
        case .noPlace:
            Text("Open Pickhour and choose a place.")
        case .empty:
            Text("No spots near this place yet.")
        case .failed:
            Text("Can't load scores right now.")
        case .spots:
            EmptyView()
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var inline: some View {
        if let top = spots.first, let score = top.score {
            Text("\(top.name) · \(score)")
        } else {
            Text("Pickhour")
        }
    }

    private var circular: some View {
        Gauge(value: Double(spots.first?.score ?? 0), in: 0...100) {
            Text("Score")
        } currentValueLabel: {
            Text(spots.first?.score.map(String.init) ?? "–")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetURL(spots.first.map { WidgetBridge.spotURL($0.id) })
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hourLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let top = spots.first {
                Text(top.name)
                    .font(.headline)
                    .lineLimit(1)
                if let score = top.score {
                    Text("Score \(score)")
                        .monospacedDigit()
                }
            } else {
                message.font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(spots.first.map { WidgetBridge.spotURL($0.id) })
    }
    #endif

    private func distance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let unit: UnitLength = entry.usesMetric ? (meters < 1000 ? .meters : .kilometers)
                                                : (meters < 1609 ? .feet : .miles)
        return measurement.converted(to: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(unit == .kilometers || unit == .miles ? 1 : 0))))
    }
}

/// Same look as the app's ScoreBadge: ring filled by score, number inside,
/// colour by tier (Meadow ≥ 60, orange 40–59, grey < 40).
struct WidgetScoreRing: View {
    let score: Int?
    let diameter: CGFloat

    private var color: Color {
        guard let score else { return .secondary }
        switch score {
        case 60...: return .accentColor
        case 40..<60: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        let line = max(3, diameter / 11)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: line)
            if let score {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            Text(score.map(String.init) ?? "–")
                .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(score.map { String(localized: "Score \($0)") } ?? String(localized: "No score")))
    }
}

#Preview(as: .systemMedium) {
    BestNowWidget()
} timeline: {
    BestNowEntry.placeholder
}
