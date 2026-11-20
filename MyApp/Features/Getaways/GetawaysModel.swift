import Foundation
import Observation

/// Loads `GET /v1/getaways` for one range. Shared by the screen and the city
/// picker's "Great This Weekend" section.
@MainActor @Observable
final class GetawaysModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var list: GetawayList?
    /// The `limit` the list was asked with (Free = 3).
    private(set) var requestedLimit = GetawayRules.freeLimit
    @ObservationIgnored private var loadedRange: GetawayRange?

    var items: [Getaway] { list?.items ?? [] }

    func load(range: GetawayRange, isPlus: Bool) async {
        // A different range replaces the list; the same range refreshes it in place.
        if loadedRange != range {
            list = nil
            phase = .loading
        }
        let limit = GetawayRules.limit(isPlus: isPlus)
        do {
            let result = try await AppConfig.apiClient.getaways(start: range.start, days: range.days, limit: limit)
            guard !Task.isCancelled else { return }
            list = result
            requestedLimit = limit
            loadedRange = range
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            Log.api.error("getaways failed: \(ErrorSummary.describe(error), privacy: .public)")
            if list == nil { phase = .failed(LoadErrorMessage.text(for: error)) }
        }
    }
}

/// The Best Now hint: the city to suggest (nil = no hint) and what it was
/// computed for, so the same weekend is not fetched again on every reload.
struct WeekendHintState {
    var city: Getaway?
    var key = ""
}

extension BestNowModel {
    /// Fetches this weekend's Getaways and decides whether Best Now shows
    /// "This weekend looks better in Lisbon" (rules in `GetawayRules.hintCity`).
    /// Runs after the rows and the forecast, so it never delays them.
    func loadWeekendHint(app: AppState) async {
        if case .currentLocation? = app.place, app.packs.isEmpty {
            await app.loadPacksIfNeeded()
        }
        let fix = app.location.coordinate
        guard let home = GetawayRules.homeSlug(place: app.place, packs: app.packs, fix: fix),
              let origin = GetawayRules.origin(place: app.place, fix: fix),
              let range = GetawayRules.range(for: .thisWeekend) else {
            weekendHint = WeekendHintState()
            return
        }
        let limit = GetawayRules.limit(isPlus: app.isPlus)
        let key = "\(home)|\(range.start.string)|\(limit)"
        guard key != weekendHint.key else { return }
        do {
            let list = try await AppConfig.apiClient.getaways(start: range.start, days: range.days, limit: limit)
            guard !Task.isCancelled else { return }
            let city = GetawayRules.hintCity(
                items: list.items, requestedLimit: limit, homeSlug: home, origin: origin,
                shownThisWeek: GetawayRules.hintShownThisWeek())
            weekendHint = WeekendHintState(city: city, key: key)
        } catch {
            // A bonus row: no error UI, retried on the next reload.
            Log.api.error("getaways hint failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }
}

extension AppState {
    /// Opens a paywall that was asked for from inside a sheet, once the sheet
    /// has closed (one sheet at a time). Same idea as `PlanRouting`.
    func presentDeferredPaywall() {
        guard let reason = deferredPaywall else { return }
        deferredPaywall = nil
        paywall = reason
    }
}

/// Opening a city from Getaways (the screen or the city picker).
@MainActor
enum GetawayNavigation {
    /// Tracks the tap, switches Best Now to the city and to its window's hour.
    /// A Free user whose hour needs Plus gets the forecast paywall after the
    /// sheet closes (`deferredPaywall`), not on top of it.
    static func open(_ city: Getaway, rank: Int, source: String, app: AppState) {
        let meters = GetawayRules.distanceMeters(from: app.location.coordinate, to: city)
        app.track("getaway_city_opened", [
            "slug": .string(city.slug),
            "rank": .number(Double(rank)),
            "source": .string(source),
            "distanceBucket": .string(GetawayRules.distanceBucket(meters: meters)),
        ])
        let pack = app.packs.first { $0.slug == city.slug }
        guard let place = GetawayRules.place(for: city, pack: pack) else { return }
        app.setPlace(place)
        let when = GetawayRules.selection(for: city)
        if when.needsPlus() && !app.isPlus {
            app.deferredPaywall = .forecast
        } else {
            app.select(when: when)
        }
    }
}
