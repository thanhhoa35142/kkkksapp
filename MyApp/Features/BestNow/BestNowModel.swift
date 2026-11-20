import CoreLocation
import Foundation
import Observation

/// Loads "best spots around the current place at the selected hour"
/// (`GET /v1/recommendations`). Shared by the iPhone tab and the iPad/Mac sidebar.
@MainActor @Observable
final class BestNowModel {
    enum Phase: Equatable {
        case idle
        case needsPlace       // no place chosen / location denied
        case loading
        case loaded
        case empty            // no spots in range (outside covered cities)
        case filteredOut      // spots exist but none match the filters
        case dark             // every result is capped "dark" (after sunset)
        case failed(String)
    }

    private(set) var items: [SpotSummary] = []
    private(set) var phase: Phase = .idle
    private(set) var updatedAt: Date?
    /// "Better at 4 PM · 88" per spot — from real hourly scores, loaded after
    /// the rows so they render first. Missing = no line.
    private(set) var outlooks: [UUID: HourOutlook] = [:]
    /// True while a reload replaces rows that are already on screen: the list
    /// dims once and swaps its content in one step (UI_SPEC §8, one motion).
    private(set) var isRefreshing = false
    /// "Today · Vondelpark · 4–6 PM" — where and when to go, from the same
    /// batch of hourly scores as the time lines. nil until they arrive, or
    /// when no loaded hour gives a good window (the plain top pick shows).
    private(set) var decision: PicnicDecision?
    /// The selected hour the decision was computed for.
    private(set) var decisionFrom: Date?
    /// Hours requested for the outlook + decision batch: a full day, so at
    /// 9 PM tomorrow's daylight is in range (Free is still clamped to
    /// tomorrow by `HourWindow`). The API accepts 1…24.
    static let decisionHours = 24

    /// Hourly forecast for the place itself (`GET /v1/weather/nearby`), next
    /// 48 h. Empty until it arrives or when it can't load — the section is
    /// simply not shown (no error UI for a bonus section).
    private(set) var weather: [NearbyWeatherPoint] = []
    /// Where / when `weather` was fetched, to skip refetching when only the
    /// filters or the selected hour change (the forecast covers every hour).
    @ObservationIgnored private var weatherFetch: (key: WeatherKey, at: Date)?

    /// Coordinate rounded to ~100 m — the same place for refetch purposes.
    struct WeatherKey: Equatable {
        let lat: Int
        let lng: Int
        init(lat: Double, lng: Double) {
            self.lat = Int((lat * 1000).rounded())
            self.lng = Int((lng * 1000).rounded())
        }
    }

    static let weatherMaxAge: TimeInterval = 10 * 60

    /// "This weekend looks better in Lisbon" (Getaways); nil city = no hint.
    var weekendHint = WeekendHintState()

    /// True when the cached forecast can't be reused for `key`.
    nonisolated static func shouldFetchWeather(
        last: (key: WeatherKey, at: Date)?, key: WeatherKey, now: Date = .now
    ) -> Bool {
        guard let last, last.key == key else { return true }
        return now.timeIntervalSince(last.at) >= weatherMaxAge
    }

    static let freeLimit = 3
    static let plusLimit = 30
    static let radiusM = 10_000.0

    /// Next 10:00 local — today if it's before 10, else tomorrow. Offered
    /// by the "It's dark out" state.
    nonisolated static func nextMorning(now: Date = .now, calendar: Calendar = .current) -> WhenSelection {
        let today10 = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        let target = now < today10 ? today10 : (calendar.date(byAdding: .day, value: 1, to: today10) ?? today10)
        return .at(target)
    }

    /// True when the Free cap may be hiding more results.
    var mayHaveMore = false

    /// Bumped by every `load`. `.task(id:)` cancels the previous load when the
    /// reload key changes, but cancellation is cooperative: a superseded load
    /// can still get its response after the newer one finished, then reset
    /// `decision` and fail its own (cancelled) hours request — leaving
    /// "It's dark out" at night, or a plain top pick by day. Only the latest
    /// load may write state.
    @ObservationIgnored private var generation = 0

    private func isCurrent(_ gen: Int) -> Bool {
        gen == generation && !Task.isCancelled
    }

    /// `forceWeather`: pull to refresh also reloads the forecast.
    func load(app: AppState, forceWeather: Bool = false) async {
        generation += 1
        let gen = generation
        guard app.place != nil else {
            phase = .needsPlace
            return
        }
        if items.isEmpty { phase = .loading } else { isRefreshing = true }
        defer { if gen == generation { isRefreshing = false } }
        guard let coordinate = await app.placeCoordinate() else {
            if isCurrent(gen) { phase = .needsPlace }
            return
        }
        guard isCurrent(gen) else { return }
        // The forecast runs beside the spots, so the rows never wait for it.
        let lat = coordinate.latitude, lng = coordinate.longitude
        async let weatherDone: Void = loadWeather(lat: lat, lng: lng, force: forceWeather)
        await loadSpots(app: app, lat: lat, lng: lng, gen: gen)
        if gen == generation { isRefreshing = false }
        await weatherDone
        guard isCurrent(gen) else { return }
        await loadWeekendHint(app: app)
    }

    private func loadSpots(app: AppState, lat: Double, lng: Double, gen: Int) async {
        let limit = app.isPlus ? Self.plusLimit : Self.freeLimit
        do {
            let list = try await AppConfig.apiClient.recommendations(
                lat: lat, lon: lng,
                radiusM: Self.radiusM, when: app.when.apiDate, limit: limit, filters: app.filters)
            guard isCurrent(gen) else { return }
            items = list.items.map(SpotSummary.init)
            outlooks = [:]
            decision = nil
            decisionFrom = nil
            app.remember(items)
            mayHaveMore = !app.isPlus && items.count >= Self.freeLimit
            updatedAt = .now
            if items.isEmpty {
                phase = app.filters.isActive ? .filteredOut : .empty
            } else if items.allSatisfy({ $0.score?.capReason == "dark" }) {
                phase = .dark
            } else {
                phase = .loaded
            }
            // Keep the rows dimmed until their time lines arrive, so the
            // swap (rows + lines) happens in one step.
            await loadOutlooks(from: app.when.resolved, isPlus: app.isPlus, gen: gen)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isCurrent(gen) else { return }
            // Keep stale rows visible when we have them (offline state).
            phase = items.isEmpty ? .failed(LoadErrorMessage.text(for: error)) : .loaded
            Log.api.error("recommendations failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// Forecast for the place. Failures keep what is on screen (offline), but
    /// never a forecast of a different place.
    private func loadWeather(lat: Double, lng: Double, force: Bool) async {
        let key = WeatherKey(lat: lat, lng: lng)
        guard force || Self.shouldFetchWeather(last: weatherFetch, key: key) else { return }
        do {
            let points = try await AppConfig.apiClient.nearbyWeather(lat: lat, lng: lng)
            guard !Task.isCancelled else { return }
            weather = points
            weatherFetch = (key: key, at: Date.now)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if weatherFetch?.key != key { weather = [] }
            Log.api.error("nearby weather failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// Hourly scores for the listed spots (one batch call), turned into the
    /// row's time line. Free: never past tomorrow (`HourWindow`).
    private func loadOutlooks(from: Date, isPlus: Bool, gen: Int) async {
        let hours = HourWindow.hours(from: from, isPlus: isPlus, maxHours: Self.decisionHours)
        let ids = items.map(\.id)
        guard hours >= 2, !ids.isEmpty else { return }
        do {
            let collection = try await AppConfig.apiClient.spots(ids: ids, from: from, hours: hours)
            guard isCurrent(gen) else { return }
            var result: [UUID: HourOutlook] = [:]
            var series: [UUID: [ScoredHour]] = [:]
            for feature in collection.features {
                let p = feature.properties
                guard let scores = p.scores, let item = items.first(where: { $0.id == p.id }) else { continue }
                series[p.id] = scores.map { ScoredHour(tsHour: $0.tsHour, score: $0.score, capReason: $0.capReason) }
                let outlook = HourOutlook.make(
                    hours: scores.map { HourOutlook.Hour(tsHour: $0.tsHour, score: $0.score, capReason: $0.capReason) },
                    from: from, current: item.score?.score, timeZone: item.timeZone)
                if let outlook { result[p.id] = outlook }
            }
            outlooks = result
            // Ranking order = the server's order of `items`.
            let candidates = items.compactMap { item -> DecisionCandidate? in
                guard let hours = series[item.id] else { return nil }
                return DecisionCandidate(spotID: item.id, spotName: item.displayName,
                                         timeZone: item.timeZone, hours: hours)
            }
            decision = DecisionPlanner.decide(candidates, from: from)
            decisionFrom = from
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Log.api.error("best now hours failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// The spot the decision card shows (one of `items`).
    var decisionSpot: SpotSummary? {
        guard let decision else { return nil }
        return items.first { $0.id == decision.window.spotID }
    }

    /// Rows under the card: every item except the one it shows; without a
    /// decision, every item after the plain top pick.
    var remainingItems: [SpotSummary] {
        if let spot = decisionSpot { return items.filter { $0.id != spot.id } }
        return Array(items.dropFirst())
    }

    /// Up to three short reasons for the card. The batch hours carry no
    /// reasons, so the row's snapshot reasons (selected hour) are used — and
    /// only the time-independent ones when the window starts later.
    func decisionReasons(limit: Int = 3) -> [Reason] {
        guard let decision, let spot = decisionSpot else { return [] }
        let all = (spot.score?.reasons ?? []).filter { ReasonLocalizer.isKnown($0.code) }
        let usable = decision.startsAtSelectedHour
            ? all.filter { !$0.code.hasPrefix("cap.") }
            : all.filter { DecisionPlanner.timeIndependentReasonCodes.contains($0.code) }
        return Array(usable.prefix(limit))
    }

    func outlookText(for spot: SpotSummary) -> String? {
        outlooks[spot.id]?.text(in: spot.timeZone)
    }
}
