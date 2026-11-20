import SwiftUI
import WidgetKit

// D7 · "Best Now" widget — where and when to picnic around the place chosen
// in the app. Reads the place (and upcoming plans) from the App Group
// (WidgetBridge) and calls the API itself: `GET /v1/recommendations` for
// the top spots, then one `GET /v1/spots?ids=&from=&hours=` for their hourly
// scores, so the timeline carries one entry per hour and the decision
// (Shared `DecisionPlanner`) — the same one as the app's Best Now card.
// After dark the decision is the next good window, not a row of capped 10s.

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

/// A spot and a time window (decision or plan), in the spot's zone.
struct WidgetWindow: Equatable {
    let spotID: UUID
    let name: String
    let timeZone: TimeZone
    let start: Date
    let end: Date
    let score: Int

    init(spotID: UUID, name: String, timeZone: TimeZone, start: Date, end: Date, score: Int) {
        self.spotID = spotID
        self.name = name
        self.timeZone = timeZone
        self.start = start
        self.end = end
        self.score = score
    }

    init(_ window: PlanWindow) {
        self.init(spotID: window.spotID, name: window.spotName, timeZone: window.timeZone,
                  start: window.start, end: window.end, score: window.score)
    }
}

/// The soonest upcoming plan from the app, with its status now.
struct WidgetPlan: Equatable {
    let window: WidgetWindow
    let status: PlanStatus?
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
    /// Where and when to go from this entry's hour; nil without hourly data.
    var decision: WidgetWindow? = nil
    /// The decision starts at this entry's hour (else it is the next window).
    var decisionStartsNow = false
    /// One short reason for the decision (parameter-free codes only).
    var reason: String? = nil
    var plan: WidgetPlan? = nil

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
    /// Hourly entries per timeline; the timeline is fetched again after
    /// `refreshHours` (≈ 12 reloads a day instead of 24).
    static let entryHours = 6
    static let refreshHours = 2

    func placeholder(in context: Context) -> BestNowEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (BestNowEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(await load().first ?? .placeholder) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BestNowEntry>) -> Void) {
        Task {
            let now = Date.now
            let entries = await load(now: now)
            let calendar = Calendar.current
            let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let refresh: Date
            if entries.first?.state == .failed {
                // Retry sooner after a failure.
                refresh = now.addingTimeInterval(15 * 60)
            } else if entries.count > 1 {
                refresh = thisHour.addingTimeInterval(TimeInterval(Self.refreshHours) * 3600 + 5 * 60)
            } else {
                // No hourly data: one entry, refreshed just after the next hour.
                refresh = thisHour.addingTimeInterval(3600 + 5 * 60)
            }
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    /// WidgetKit kills an extension that runs too long, and `load` makes up to
    /// four sequential requests (8 s each). The optional hourly fetch is only
    /// worth starting while the budget is mostly intact; without it the
    /// widget still shows the single-entry view from the recommendations.
    private static let hoursFetchDeadline: TimeInterval = 8

    private func load(now: Date = .now) async -> [BestNowEntry] {
        let started = Date()
        guard let snapshot = WidgetBridge.load() else {
            return [BestNowEntry(date: now, placeName: "", hour: now, isNextMorning: false,
                                 state: .noPlace, usesMetric: true)]
        }
        let isPlus = snapshot.isPlus ?? false
        let plan = await Self.planInfo(WidgetBridge.loadPlans().first { $0.end > now },
                                       snapshot: snapshot, now: now, isPlus: isPlus)
        do {
            let result = try await WidgetAPI.recommendations(snapshot, when: nil)
            guard !result.items.isEmpty else {
                return [BestNowEntry(date: now, placeName: snapshot.placeName, hour: now, isNextMorning: false,
                                     state: .empty, usesMetric: snapshot.usesMetric, plan: plan)]
            }
            let calendar = Calendar.current
            let thisHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let hours = HourWindow.hours(from: thisHour, isPlus: isPlus, maxHours: 24, now: now, calendar: calendar)
            var series: [UUID: [ScoredHour]] = [:]
            if hours >= 2, Date().timeIntervalSince(started) < Self.hoursFetchDeadline {
                series = (try? await WidgetAPI.hours(snapshot, ids: result.items.map(\.id),
                                                     from: thisHour, hours: hours)) ?? [:]
            }
            if series.isEmpty {
                return [try await singleEntry(result, snapshot: snapshot, now: now, plan: plan)]
            }
            let entries = Self.hourlyEntries(result, series: series, snapshot: snapshot, now: now,
                                             thisHour: thisHour, hours: hours, plan: plan)
            // No window in reach (e.g. Free after dark tomorrow): keep the old
            // "tomorrow morning" view rather than a row of capped scores.
            if entries.first?.decision == nil {
                return [try await singleEntry(result, snapshot: snapshot, now: now, plan: plan)]
            }
            return entries
        } catch {
            return [BestNowEntry(date: now, placeName: snapshot.placeName, hour: now, isNextMorning: false,
                                 state: .failed, usesMetric: snapshot.usesMetric, plan: plan)]
        }
    }

    /// One entry per hour from `thisHour`, each with its own ranking and
    /// decision computed from the same hourly scores.
    static func hourlyEntries(_ result: WidgetAPI.Response, series: [UUID: [ScoredHour]],
                              snapshot: WidgetBridge.Snapshot, now: Date, thisHour: Date,
                              hours: Int, plan: WidgetPlan?) -> [BestNowEntry] {
        let candidates = result.items.compactMap { item -> DecisionCandidate? in
            guard let itemHours = series[item.id] else { return nil }
            return DecisionCandidate(spotID: item.id, spotName: item.displayName, timeZone: item.timeZone,
                                     hours: itemHours)
        }
        var entries: [BestNowEntry] = []
        for index in 0..<max(1, min(entryHours, hours)) {
            let hour = thisHour.addingTimeInterval(TimeInterval(index) * 3600)
            let date = index == 0 ? now : hour
            var spots = result.items.map { item in
                let score = index == 0
                    ? item.score?.score
                    : series[item.id]?.first { abs($0.tsHour.timeIntervalSince(hour)) < 60 }?.score
                return WidgetSpot(id: item.id, name: item.displayName, score: score, distanceM: item.distanceM)
            }
            if index > 0 { spots.sort { ($0.score ?? -1) > ($1.score ?? -1) } }
            let decision = DecisionPlanner.decide(candidates, from: hour)
            // The response's reasons describe the current hour only.
            let codes = decision.flatMap { d in result.items.first { $0.id == d.window.spotID } }?
                .score?.reasons?.map(\.code) ?? []
            let usable = (decision?.startsAtSelectedHour == true && index == 0)
                ? codes.filter { !$0.hasPrefix("cap.") }
                : codes.filter { DecisionPlanner.timeIndependentReasonCodes.contains($0) }
            entries.append(BestNowEntry(
                date: date, placeName: snapshot.placeName, hour: hour, isNextMorning: false,
                state: .spots(spots), usesMetric: snapshot.usesMetric,
                decision: decision.map { WidgetWindow($0.window) },
                decisionStartsNow: decision?.startsAtSelectedHour ?? false,
                reason: usable.lazy.compactMap(WidgetReason.text).first,
                plan: plan.flatMap { $0.window.end > date ? $0 : nil }))
        }
        return entries
    }

    /// Without hourly scores: the top spots now, or tomorrow morning's when
    /// every result is capped "dark".
    private func singleEntry(_ first: WidgetAPI.Response, snapshot: WidgetBridge.Snapshot,
                             now: Date, plan: WidgetPlan?) async throws -> BestNowEntry {
        var hour = now
        var nextMorning = false
        var result = first
        if result.items.allSatisfy({ $0.score?.capReason == "dark" }) {
            hour = Self.nextMorning(after: now)
            nextMorning = true
            result = try await WidgetAPI.recommendations(snapshot, when: hour)
        }
        let spots = result.items.map {
            WidgetSpot(id: $0.id, name: $0.displayName, score: $0.score?.score, distanceM: $0.distanceM)
        }
        return BestNowEntry(date: now, placeName: snapshot.placeName, hour: hour, isNextMorning: nextMorning,
                            state: spots.isEmpty ? .empty : .spots(spots), usesMetric: snapshot.usesMetric,
                            plan: plan)
    }

    /// The plan with its status: the server's for a synced plan, else from
    /// the latest hourly scores (Shared `PlanStatus`); status nil when the hours are out of reach (Free past
    /// tomorrow) or the call fails.
    static func planInfo(_ plan: PlanSnapshot?, snapshot: WidgetBridge.Snapshot, now: Date,
                         isPlus: Bool) async -> WidgetPlan? {
        guard let plan else { return nil }
        let window = WidgetWindow(spotID: plan.spotID, name: plan.spotName, timeZone: plan.timeZone,
                                  start: plan.start, end: plan.end, score: plan.scoreAtSave)
        let calendar = Calendar.current
        let nowHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let from = max(plan.start, nowHour)
        let wanted = Int((plan.end.timeIntervalSince(from) / 3600).rounded(.up))
        let allowed = HourWindow.hours(from: from, isPlus: isPlus, maxHours: 24, now: now, calendar: calendar)
        let count = min(wanted, allowed)
        // Fresh scores first. A synced plan's server status (as of the app's
        // last sync) is only the fallback when the fetch fails or is empty:
        // a stale "good" is worse than a small disagreement with the app.
        var status: PlanStatus?
        if count >= 1,
           let series = try? await WidgetAPI.hours(snapshot, ids: [plan.spotID], from: from, hours: count),
           let hours = series[plan.spotID], !hours.isEmpty {
            status = PlanStatus.classify(hours: hours, start: from, end: plan.end, scoreAtSave: plan.scoreAtSave)
        }
        return WidgetPlan(window: window, status: status ?? plan.serverStatus)
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
                struct Code: Decodable { let code: String }
                let score: Int
                let capReason: String?
                let reasons: [Code]?
            }
            let id: UUID
            let kind: String
            let name: String?
            let names: [String: String]?
            let city: String?
            let tz: String?
            let distanceM: Double
            let score: Score?

            var timeZone: TimeZone { tz.flatMap(TimeZone.init(identifier:)) ?? .current }

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

    /// `GET /v1/spots?ids=&from=&hours=` (GeoJSON, not enveloped) — only
    /// the hourly scores are decoded.
    private struct HoursCollection: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                struct Hour: Decodable {
                    let tsHour: Date
                    let score: Int
                    let capReason: String?
                }
                let id: UUID
                let scores: [Hour]?
            }
            let properties: Properties
        }
        let features: [Feature]
    }

    static func recommendations(_ snapshot: WidgetBridge.Snapshot, when: Date?) async throws -> Response {
        var query = [
            URLQueryItem(name: "lat", value: String(snapshot.latitude)),
            URLQueryItem(name: "lon", value: String(snapshot.longitude)),
            URLQueryItem(name: "radius", value: "10000"),
            URLQueryItem(name: "limit", value: "3"),
        ]
        if let when { query.append(URLQueryItem(name: "when", value: ISO8601DateFormatter().string(from: when))) }
        let data = try await get(snapshot, path: "/v1/recommendations", query: query)
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }

    /// Hourly scores per spot from `from` (1…24 hours).
    static func hours(_ snapshot: WidgetBridge.Snapshot, ids: [UUID], from: Date,
                      hours: Int) async throws -> [UUID: [ScoredHour]] {
        let query = [
            URLQueryItem(name: "ids", value: ids.map(\.uuidString).joined(separator: ",")),
            URLQueryItem(name: "from", value: ISO8601DateFormatter().string(from: from)),
            URLQueryItem(name: "hours", value: String(min(max(hours, 1), 24))),
        ]
        let data = try await get(snapshot, path: "/v1/spots", query: query)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = PlanLink.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(text)")
            }
            return date
        }
        let collection = try decoder.decode(HoursCollection.self, from: data)
        var result: [UUID: [ScoredHour]] = [:]
        for feature in collection.features {
            guard let scores = feature.properties.scores else { continue }
            result[feature.properties.id] = scores.map {
                ScoredHour(tsHour: $0.tsHour, score: $0.score, capReason: $0.capReason)
            }
        }
        return result
    }

    private static func get(_ snapshot: WidgetBridge.Snapshot, path: String,
                            query: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(string: snapshot.apiBaseURL) else { throw URLError(.badURL) }
        components.path = path
        components.queryItems = query
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("pickhour-widget", forHTTPHeaderField: "X-Client")
        request.setValue(Locale.preferredLanguages.prefix(3).joined(separator: ","), forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Widget-local phrasing of the reason codes that need no parameters (the
/// app's ReasonLocalizer isn't in this target). Others: no reason line.
enum WidgetReason {
    static func text(_ code: String) -> String? {
        switch code {
        case "weather.cloudy": String(localized: "Overcast")
        case "crowd.low": String(localized: "Usually quiet at this hour")
        case "crowd.moderate": String(localized: "Some people around")
        case "amenity.well_equipped": String(localized: "Good facilities nearby")
        case "fresh.recent": String(localized: "Recently verified")
        default: nil
        }
    }
}

/// Hours and days in the spot's time zone.
enum WidgetFormat {
    static func hour(_ date: Date, in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "4 PM–6 PM".
    static func range(_ window: WidgetWindow) -> String {
        "\(hour(window.start, in: window.timeZone))–\(hour(window.end, in: window.timeZone))"
    }

    /// "Today", "Tomorrow", else the short weekday.
    static func day(_ window: WidgetWindow) -> String {
        var calendar = Calendar.current
        calendar.timeZone = window.timeZone
        if calendar.isDateInToday(window.start) { return String(localized: "Today") }
        if calendar.isDateInTomorrow(window.start) { return String(localized: "Tomorrow") }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = window.timeZone
        return window.start.formatted(style)
    }

    /// "Today 4 PM–6 PM".
    static func when(_ window: WidgetWindow) -> String {
        "\(day(window)) \(range(window))"
    }

    static func status(_ status: PlanStatus?) -> String? {
        switch status {
        case .good: String(localized: "Still looks good")
        case .worse: String(localized: "Not as good as planned")
        case .notRecommended: String(localized: "Not recommended now")
        case nil: nil
        }
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

    /// What the widget leads with: a plan within a day, else the decision,
    /// else the top spot.
    private enum Focus {
        case plan(WidgetPlan)
        case decision(WidgetWindow)
        case spot(WidgetSpot)
        case none
    }

    private var focus: Focus {
        if let plan = entry.plan, plan.window.start < entry.date.addingTimeInterval(24 * 3600) {
            return .plan(plan)
        }
        if let decision = entry.decision { return .decision(decision) }
        if let top = spots.first { return .spot(top) }
        return .none
    }

    private var focusURL: URL {
        switch focus {
        case .plan(let plan): WidgetBridge.spotURL(plan.window.spotID, at: plan.window.start)
        case .decision(let window): WidgetBridge.spotURL(window.spotID, at: window.start)
        case .spot(let spot): WidgetBridge.spotURL(spot.id, at: entryHourForLinks)
        case .none: WidgetBridge.appURL
        }
    }

    /// Later timeline entries show another hour's scores: open that hour.
    /// (The first entry is dated "now" and opens the current hour: no `at`.)
    private var entryHourForLinks: Date? {
        entry.isNextMorning || entry.date == entry.hour ? entry.hour : nil
    }

    private var spots: [WidgetSpot] {
        if case .spots(let s) = entry.state { return s }
        return []
    }

    private var hourLabel: String {
        switch focus {
        case .plan:
            return String(localized: "Your plan")
        case .decision:
            return entry.decisionStartsNow ? String(localized: "Now") : String(localized: "Next good time")
        default:
            break
        }
        if entry.isNextMorning {
            let hour = entry.hour.formatted(.dateTime.hour())
            return Calendar.current.isDateInToday(entry.hour)
                ? String(localized: "This morning \(hour)")
                : String(localized: "Tomorrow \(hour)")
        }
        return String(localized: "Now")
    }

    // Small: the one answer.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            switch focus {
            case .plan(let plan):
                WidgetScoreRing(score: plan.window.score, diameter: 36)
                windowText(plan.window)
                if let status = WidgetFormat.status(plan.status) {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .decision(let window):
                WidgetScoreRing(score: window.score, diameter: 36)
                windowText(window)
            case .spot(let top):
                WidgetScoreRing(score: top.score, diameter: 40)
                Text(top.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            case .none:
                message
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(focusURL)
    }

    /// Name (2 lines) + "Today 4 PM–6 PM".
    private func windowText(_ window: WidgetWindow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(window.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(WidgetFormat.when(window))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // Medium: the answer (plan / decision), then spots; each row tappable.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if case .none = focus {
                Spacer(minLength: 0)
                message
                Spacer(minLength: 0)
            } else {
                ForEach(Array(mediumRows.prefix(3).enumerated()), id: \.offset) { _, row in
                    Link(destination: row.url) {
                        HStack(spacing: 10) {
                            WidgetScoreRing(score: row.score, diameter: 30)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                if let detail = row.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            if let trailing = row.trailing {
                                Text(trailing)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(focusURL)
    }

    private struct Row {
        let title: String
        let detail: String?
        let trailing: String?
        let score: Int?
        let url: URL
    }

    /// Plan (if any), decision, then the other spots.
    private var mediumRows: [Row] {
        var rows: [Row] = []
        var shown: Set<UUID> = []
        if case .plan(let plan) = focus {
            let detail = [WidgetFormat.when(plan.window), WidgetFormat.status(plan.status)]
                .compactMap { $0 }.joined(separator: " · ")
            rows.append(Row(title: plan.window.name, detail: detail, trailing: nil, score: plan.window.score,
                            url: WidgetBridge.spotURL(plan.window.spotID, at: plan.window.start)))
        }
        if let window = entry.decision {
            let detail = [WidgetFormat.when(window), entry.reason].compactMap { $0 }.joined(separator: " · ")
            rows.append(Row(title: window.name, detail: detail, trailing: nil, score: window.score,
                            url: WidgetBridge.spotURL(window.spotID, at: window.start)))
            shown.insert(window.spotID)
        }
        for spot in spots where !shown.contains(spot.id) {
            rows.append(Row(title: spot.name, detail: nil, trailing: distance(spot.distanceM), score: spot.score,
                            url: WidgetBridge.spotURL(spot.id, at: entryHourForLinks)))
        }
        return rows
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
    /// One short line per state — never just the app name.
    @ViewBuilder
    private var inline: some View {
        switch focus {
        case .plan(let plan):
            Text("\(plan.window.name) · \(WidgetFormat.hour(plan.window.start, in: plan.window.timeZone))")
        case .decision(let window):
            Text("\(window.name) · \(WidgetFormat.hour(window.start, in: window.timeZone))")
        case .spot(let top):
            if let score = top.score {
                Text("\(top.name) · \(score)")
            } else {
                Text(top.name)
            }
        case .none:
            switch entry.state {
            case .noPlace: Text("Choose a place in Pickhour")
            case .empty: Text("No picnic spots nearby")
            case .failed, .spots: Text("Scores unavailable")
            }
        }
    }

    @ViewBuilder
    private var circular: some View {
        let score: Int? = switch focus {
        case .plan(let plan): plan.window.score
        case .decision(let window): window.score
        case .spot(let top): top.score
        case .none: nil
        }
        Group {
            if let score {
                Gauge(value: Double(score), in: 0...100) {
                    Text("Score")
                } currentValueLabel: {
                    Text(score, format: .number)
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: emptySymbol)
                        .font(.title3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(emptyLabel))
            }
        }
        .widgetURL(focusURL)
    }

    private var emptySymbol: String {
        switch entry.state {
        case .noPlace: "mappin.slash"
        case .empty: "map"
        case .failed, .spots: "wifi.slash"
        }
    }

    private var emptyLabel: String {
        switch entry.state {
        case .noPlace: String(localized: "Choose a place in Pickhour")
        case .empty: String(localized: "No picnic spots nearby")
        case .failed, .spots: String(localized: "Scores unavailable")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch focus {
            case .plan(let plan):
                Text("\(hourLabel) · \(WidgetFormat.when(plan.window))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(plan.window.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(WidgetFormat.status(plan.status) ?? String(localized: "Score \(plan.window.score)"))
                    .lineLimit(1)
            case .decision(let window):
                Text(WidgetFormat.when(window))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(window.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.reason ?? String(localized: "Score \(window.score)"))
                    .lineLimit(1)
            case .spot(let top):
                Text(hourLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(top.name)
                    .font(.headline)
                    .lineLimit(1)
                if let score = top.score {
                    Text("Score \(score)")
                        .monospacedDigit()
                }
            case .none:
                Text(hourLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                message.font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(focusURL)
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

    /// Follows Dynamic Type a little; widget space is fixed, so clamp it.
    @ScaledMetric(relativeTo: .subheadline) private var typeScale: CGFloat = 1
    private var size: CGFloat { diameter * min(max(typeScale, 1), 1.2) }

    private var color: Color {
        guard let score else { return .secondary }
        switch score {
        case 60...: return .accentColor
        case 40..<60: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        let line = max(3, size / 11)
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
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(score.map { String(localized: "Score \($0)") } ?? String(localized: "No score")))
    }
}

#Preview(as: .systemMedium) {
    BestNowWidget()
} timeline: {
    BestNowEntry.placeholder
}
