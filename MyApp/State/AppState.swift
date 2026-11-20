import CoreLocation
import Foundation
import WidgetKit
import Observation
import StoreKit

/// Where Best Now looks.
enum Place: Codable, Equatable {
    case currentLocation
    case city(slug: String, name: String, latitude: Double, longitude: Double)

    var title: String {
        switch self {
        case .currentLocation: String(localized: "Current Location")
        case .city(_, let name, _, _): name
        }
    }
}

/// Who's coming. Stored and sent as a device pref, but no longer asked in
/// onboarding: the backend doesn't rank by it yet (kept for when it does).
enum Companion: String, CaseIterable, Codable, Identifiable {
    case kids, dog, friends, couple
    var id: String { rawValue }

    var title: String {
        switch self {
        case .kids: String(localized: "Kids")
        case .dog: String(localized: "Dog")
        case .friends: String(localized: "Friends")
        case .couple: String(localized: "Just us two")
        }
    }
}

/// A locked forecast day's best hour — data Free already sees in the
/// Spot Detail week strip, shown again on the paywall it opens.
struct ForecastTeaser: Equatable {
    let day: Date
    let hour: Date
    let score: Int
    let timeZone: TimeZone

    /// "Saturday peaks at 87 at 2 PM."
    var text: String {
        var weekday = Date.FormatStyle.dateTime.weekday(.wide)
        weekday.timeZone = timeZone
        return String(localized: "\(day.formatted(weekday)) peaks at \(score) at \(Format.hour(hour, in: timeZone)).")
    }
}

enum AppTab: Hashable {
    case bestNow, map, saved, settings
}

/// The plan sheet: one of the user's plans (local id), or a shared plan by
/// token (link, follower push, followed row).
enum PlanSheet: Identifiable, Hashable {
    case own(planID: UUID)
    case shared(token: String)

    var id: String {
        switch self {
        case .own(let planID): "own-\(planID.uuidString)"
        case .shared(let token): "shared-\(token)"
        }
    }
}

/// App-wide UI state shared by every screen and layout (compact tabs,
/// iPad/Mac split view). Layout-independent on purpose: folding a foldable
/// or resizing a window swaps layouts without losing the selection,
/// the hour or the place (UI_SPEC §10.3).
@MainActor @Observable
final class AppState {
    // Shared selection
    var when: WhenSelection = .now
    var selectedSpotID: UUID?
    var selectedTab: AppTab = .bestNow
    /// Non-nil = paywall sheet open, opened from this touch point.
    var paywall: PaywallReason?
    /// Real Free-plan data for the locked day that opened the paywall
    /// ("Saturday peaks at 87 at 2 PM"). Cleared when the paywall closes.
    var paywallTeaser: ForecastTeaser?
    /// Non-nil = exit survey showing for a paywall opened from this point.
    var survey: PaywallReason?
    private var lastPaywallReason: PaywallReason?
    private var purchasedInPaywall = false
    /// Bumped to ask the map to center on `selectedSpotID`.
    var mapFocusVersion = 0
    /// Non-nil = plan sheet open (own plan or a shared one).
    var planSheet: PlanSheet?
    /// Paywall to open once the plan sheet has closed (one sheet at a time).
    var deferredPaywall: PaywallReason?
    /// Non-nil = Getaways sheet open, opened from this entry point.
    var getawaysSource: GetawaySource?

    // Persisted preferences
    private(set) var place: Place?
    private(set) var companions: Set<Companion> = []
    private(set) var filters = SpotFilters()

    // Plan
    private(set) var entitlement: Entitlement?
    var isPlus: Bool { entitlement?.isPlus ?? false }

    // Data shared across screens
    private(set) var packs: [CityPack] = []
    private(set) var packsError: String?
    /// Last known summary per spot — instant headers when opening a detail.
    private(set) var summaries: [UUID: SpotSummary] = [:]

    let location = LocationProvider()
    let alerts = AlertsStore()
    let planSync = PlanSyncStore()
    let nudge = NudgeStore()

    private let defaults = UserDefaults.standard
    private let api = AppConfig.apiClient

    init() {
        if UITestFixtures.isActive {
            place = UITestFixtures.place
        } else if let data = defaults.data(forKey: "place"),
           let decoded = try? JSONDecoder().decode(Place.self, from: data) {
            place = decoded
        }
        if let raw = defaults.array(forKey: "companions") as? [String] {
            companions = Set(raw.compactMap(Companion.init(rawValue:)))
        }
        if let data = defaults.data(forKey: "filters"),
           let decoded = try? JSONDecoder().decode(SpotFilters.self, from: data) {
            filters = decoded
        }
        nudge.homeProvider = { [weak self] in self?.nudgeHome() }
    }

    func setFilters(_ value: SpotFilters) {
        filters = value
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "filters")
        }
    }

    // MARK: - Preferences

    func setPlace(_ newPlace: Place) {
        place = newPlace
        if let data = try? JSONEncoder().encode(newPlace) {
            defaults.set(data, forKey: "place")
        }
    }

    func setCompanions(_ value: Set<Companion>) {
        companions = value
        defaults.set(value.map(\.rawValue), forKey: "companions")
        // Coming with a dog: start with the dog-area filter on (UI_SPEC S0).
        if value.contains(.dog) && !filters.isActive {
            var next = filters
            next.amenities.insert("dog_area")
            setFilters(next)
        }
    }

    /// Coordinate for the current place (asks for a fresh fix when it is the
    /// user's location).
    func placeCoordinate() async -> CLLocationCoordinate2D? {
        let coordinate: CLLocationCoordinate2D?
        switch place {
        case .currentLocation:
            coordinate = await location.currentCoordinate()
        case .city(_, _, let lat, let lon):
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        case nil:
            coordinate = nil
        }
        if let coordinate, let place { updateWidget(place: place, coordinate: coordinate) }
        return coordinate
    }

    /// Home for the good-day push: the chosen city's centre, or the last known
    /// fix. Never asks for a location (unlike `placeCoordinate()`); the store
    /// rounds it to ~1 km.
    func nudgeHome() -> NudgeHome? {
        switch place {
        case .currentLocation:
            guard location.isAuthorized, let coordinate = location.coordinate else { return nil }
            return NudgeHome(source: .location, coordinate: coordinate)
        case .city(_, _, let lat, let lon):
            return NudgeHome(source: .city, latitude: lat, longitude: lon)
        case nil:
            return nil
        }
    }

    /// Hands the widget a coarse point (WidgetBridge rounds to ~1 km) and
    /// reloads it only when something it shows changed.
    private func updateWidget(place: Place, coordinate: CLLocationCoordinate2D) {
        let snapshot = WidgetBridge.Snapshot(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            placeName: place.title, apiBaseURL: AppConfig.apiBaseURL.absoluteString,
            usesMetric: Self.usesMetricDistance, isPlus: isPlus)
        var rounded = snapshot
        rounded.latitude = (snapshot.latitude * 100).rounded() / 100
        rounded.longitude = (snapshot.longitude * 100).rounded() / 100
        guard WidgetBridge.load() != rounded else { return }
        WidgetBridge.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.bestNowKind)
    }

    /// Keeps the widget's Free / Plus hour limit in step with the plan
    /// (the snapshot is otherwise written only when the place changes).
    func syncWidgetEntitlement() {
        guard var snapshot = WidgetBridge.load(), snapshot.isPlus != isPlus else { return }
        snapshot.isPlus = isPlus
        WidgetBridge.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.bestNowKind)
    }

    private static var usesMetricDistance: Bool {
        switch UnitPreference.current(UnitPreference.distanceKey) {
        case .metric: true
        case .imperial: false
        case .automatic: Locale.current.measurementSystem != .us
        }
    }

    // MARK: - Selection

    func remember(_ items: [SpotSummary]) {
        for item in items { summaries[item.id] = item }
    }

    /// Opens a spot from anywhere (list, deep link, notification).
    func open(spotID: UUID, focusMap: Bool) {
        selectedSpotID = spotID
        if focusMap { mapFocusVersion += 1 }
    }

    /// An hour Spot Detail should show when it opens (a plan, the decision
    /// card, a shared link with `?at=`). Consumed once by the detail for
    /// that spot, whichever container shows it (push, map sheet, inspector).
    struct DetailFocus: Equatable {
        let spotID: UUID
        let hour: Date
    }

    var detailFocus: DetailFocus?

    /// Opens a spot at an hour. The focus is set before the selection so the
    /// detail finds it when it loads.
    func open(spotID: UUID, at hour: Date, focusMap: Bool) {
        detailFocus = DetailFocus(spotID: spotID, hour: hour)
        open(spotID: spotID, focusMap: focusMap)
    }

    /// Picks an hour; returns false (and shows the paywall) when it needs Plus.
    @discardableResult
    func select(when newValue: WhenSelection) -> Bool {
        if newValue.needsPlus() && !isPlus {
            paywall = .forecast
            return false
        }
        when = newValue
        return true
    }

    // MARK: - Bootstrap & plan

    /// Time of the last (attempted) device registration, in memory only: a
    /// cold launch starts empty and `bootstrap()` registers.
    @ObservationIgnored private var lastDeviceRegisterAt: Date?

    /// Registers this install (no location, no PII); the server also bumps
    /// `last_seen_at`. Stamped before the request so a foreground event
    /// racing the launch registration is throttled; a failure clears it.
    private func registerDevice() async {
        lastDeviceRegisterAt = .now
        do {
            _ = try await api.registerDevice(DeviceRegisterRequest(
                id: DeviceIdentity.deviceID,
                apnsToken: KeychainStore.string(for: .apnsToken),
                apnsEnv: KeychainStore.string(for: .apnsEnv),
                locale: Locale.preferredLanguages.first,
                tz: TimeZone.current.identifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                prefs: ["companions": .array(companions.map { .string($0.rawValue) })]
            ))
        } catch {
            lastDeviceRegisterAt = nil
            Log.api.error("device register failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// Back from the background: re-registers (refreshes `last_seen_at`) at
    /// most once an hour. Cold launch is covered by `bootstrap()`.
    func touchDeviceIfStale(now: Date = .now) async {
        if let last = lastDeviceRegisterAt, now.timeIntervalSince(last) < 3600 { return }
        await registerDevice()
    }

    // MARK: - App version (force update)

    /// `.required` replaces the whole UI (RootView); `.available` shows a
    /// dismissible prompt once.
    var appUpdate: AppUpdateState = .none
    @ObservationIgnored private var lastVersionCheckAt: Date?

    /// Asks the server for its version policy (launch, then at most hourly on
    /// foreground). Offline or a server error: the app keeps working — a
    /// blocked build still learns it from the first 426.
    func checkAppVersion(now: Date = .now) async {
        if let last = lastVersionCheckAt, now.timeIntervalSince(last) < 3600 { return }
        lastVersionCheckAt = now
        AppUpdateSignal.onUpgradeRequired = { [weak self] url in
            self?.appUpdate = .required(storeURL: url)
        }
        do {
            let config = try await api.appConfig()
            let storeURL = config.storeUrl.flatMap(URL.init(string:))
            switch config.status {
            case .updateRequired:
                appUpdate = .required(storeURL: storeURL)
            case .updateAvailable:
                if appUpdate == .none { appUpdate = .available(storeURL: storeURL) }
            case .ok, .unknown:
                if case .required = appUpdate { appUpdate = .none }
            }
        } catch {
            lastVersionCheckAt = nil
            Log.api.error("app config failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// Registers this install and loads the plan.
    ///
    /// Only the real dependencies are ordered: everything that needs the
    /// device secret (entitlement, alerts, nudge, plan sync, events) waits for
    /// `registerDevice()`; the version check doesn't, so it runs beside it.
    /// After registration the independent steps overlap (all `@MainActor`, so
    /// they interleave at their awaits) — a slow call no longer delays the
    /// ones behind it, which matters when launch happens on a weak network.
    func bootstrap() async {
        let deviceID = DeviceIdentity.deviceID
        async let versionCheck: Void = checkAppVersion()
        await registerDevice()
        if !UITestFixtures.isActive {
            Task.detached(priority: .utility) { [api] in await AppAttestor.attestIfNeeded(api: api) }
        }
        listenForTransactions()
        planSync.requestSync()

        // APNs can rotate the token (restore, reinstall, OS update); asking on
        // every launch hands the current one to handleDeviceToken, which
        // re-registers it. No prompt: only runs when already authorized.
        async let push: Void = PushManager.shared.registerIfAuthorized()
        // Ordered pair: linking needs the freshly loaded entitlement (`isPlus`).
        async let entitlementAndLink: Void = refreshAndLinkEntitlements()
        async let alertRules: Void = alerts.load()
        async let nudgeSync: Void = nudge.syncIfNeeded()
        _ = await (versionCheck, push, entitlementAndLink, alertRules, nudgeSync)

        await EventQueue.shared.flush(client: api, deviceID: deviceID)
    }

    private func refreshAndLinkEntitlements() async {
        await refreshEntitlement()
        await linkCurrentEntitlements()
    }

    private var transactionListener: Task<Void, Never>?

    /// Renewals, Ask to Buy approvals and purchases made on another device
    /// arrive here; each is linked to the backend and finished.
    private func listenForTransactions() {
        guard transactionListener == nil else { return }
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.link(signedTransaction: result.jwsRepresentation)
                if case .verified(let transaction) = result { await transaction.finish() }
            }
        }
    }

    func refreshEntitlement() async {
        do {
            entitlement = try await api.entitlement(deviceID: DeviceIdentity.deviceID)
        } catch {
            Log.store.error("entitlement failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
    }

    /// Sends a StoreKit signed transaction to the backend, then reloads the plan.
    func link(signedTransaction jws: String) async {
        do {
            _ = try await api.linkTransaction(signedTransaction: jws)
        } catch {
            Log.store.error("link transaction failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
        await refreshEntitlement()
    }

    /// Launch: a device that holds an App Store entitlement the backend does
    /// not know yet links it without the user tapping Restore. This is how a
    /// Family Sharing member (who never purchases on this device), a
    /// reinstall and a second device get Plus. No App Store sign-in prompt:
    /// `currentEntitlements` reads the local StoreKit state only.
    private func linkCurrentEntitlements() async {
        guard !isPlus else { return }
        var linked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PaywallSheet.productIDs.contains(transaction.productID) else { continue }
            do {
                _ = try await api.linkTransaction(
                    signedTransaction: result.jwsRepresentation)
                linked = true
            } catch {
                Log.store.error("link current entitlement failed: \(ErrorSummary.describe(error), privacy: .public)")
            }
        }
        if linked { await refreshEntitlement() }
    }

    /// Restore: re-syncs with the App Store and links current entitlements.
    func restorePurchases() async {
        do { try await AppStore.sync() } catch {
            Log.store.error("AppStore.sync failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
        for await result in Transaction.currentEntitlements {
            await link(signedTransaction: result.jwsRepresentation)
        }
        await refreshEntitlement()
    }

    // MARK: - Packs

    func loadPacksIfNeeded() async {
        guard packs.isEmpty else { return }
        do {
            packs = try await api.packs()
            packsError = nil
        } catch {
            packsError = error.localizedDescription
        }
    }

    // MARK: - Paywall

    func paywallDidAppear(_ reason: PaywallReason) {
        lastPaywallReason = reason
        purchasedInPaywall = false
    }

    func paywallDidPurchase() { purchasedInPaywall = true }

    /// Root paywall sheet closed. Not called for the paywall pushed inside
    /// the Alert editor — no survey on top of an unsaved form.
    func paywallDidDismiss() {
        paywallTeaser = nil
        guard !purchasedInPaywall, !isPlus, let reason = lastPaywallReason else { return }
        lastPaywallReason = nil
        if PaywallSurvey.registerDismissal() {
            // Let the sheet finish closing before the dialog appears.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                survey = reason
            }
        }
    }

    // MARK: - Analytics

    /// Called when the app moves to the background: the queue is sent under a
    /// background-task assertion, so a flush that started now isn't suspended
    /// mid-request (and a short list of events isn't stranded until next launch).
    func flushEventsForBackground() async {
        let client = api
        let deviceID = DeviceIdentity.deviceID
        try? await withBackgroundTask(name: "app.pickhour.events") {
            await EventQueue.shared.flush(client: client, deviceID: deviceID)
        }
    }

    func track(_ name: String, _ props: [String: JSONValue]? = nil) {
        Task { await EventQueue.shared.enqueue(AppEvent(name: name, props: props)) }
    }

    // MARK: - Privacy

    /// Settings → Delete My Data: server device row, local queue, keychain.
    func deleteMyData() async {
        let id = DeviceIdentity.deviceID
        do { try await api.deleteDevice(id: id) } catch {
            Log.api.error("delete device failed: \(ErrorSummary.describe(error), privacy: .public)")
        }
        await EventQueue.shared.clear()
        KeychainStore.delete(.deviceID)
        KeychainStore.delete(.apnsToken)
        KeychainStore.delete(.apnsEnv)
        KeychainStore.delete(.deviceSecret)
        defaults.removeObject(forKey: "place")
        defaults.removeObject(forKey: "companions")
        defaults.removeObject(forKey: "filters")
        place = nil
        companions = []
        filters = SpotFilters()
        alerts.reset()
        planSync.reset()
        nudge.reset()
        planSheet = nil
        PaywallSurvey.reset()
        WidgetBridge.clear()
        WidgetCenter.shared.reloadAllTimelines()
        CrowdReportLog.reset()
        entitlement = nil
    }
}
