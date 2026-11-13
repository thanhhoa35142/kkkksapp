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

/// Who's coming — onboarding step 3, light personalization (spec §8).
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

enum AppTab: Hashable {
    case bestNow, map, saved, settings
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
    /// Non-nil = exit survey showing for a paywall opened from this point.
    var survey: PaywallReason?
    private var lastPaywallReason: PaywallReason?
    private var purchasedInPaywall = false
    /// Bumped to ask the map to center on `selectedSpotID`.
    var mapFocusVersion = 0

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

    private let defaults = UserDefaults.standard
    private let api = AppConfig.apiClient

    init() {
        if let data = defaults.data(forKey: "place"),
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

    /// Hands the widget a coarse point (WidgetBridge rounds to ~1 km) and
    /// reloads it only when something it shows changed.
    private func updateWidget(place: Place, coordinate: CLLocationCoordinate2D) {
        let snapshot = WidgetBridge.Snapshot(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            placeName: place.title, apiBaseURL: AppConfig.apiBaseURL.absoluteString,
            usesMetric: Self.usesMetricDistance)
        var rounded = snapshot
        rounded.latitude = (snapshot.latitude * 100).rounded() / 100
        rounded.longitude = (snapshot.longitude * 100).rounded() / 100
        guard WidgetBridge.load() != rounded else { return }
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

    /// Registers this install (no location, no PII) and loads the plan.
    func bootstrap() async {
        let deviceID = DeviceIdentity.deviceID
        do {
            _ = try await api.registerDevice(DeviceRegisterRequest(
                id: deviceID,
                apnsToken: KeychainStore.string(for: .apnsToken),
                apnsEnv: KeychainStore.string(for: .apnsEnv),
                locale: Locale.preferredLanguages.first,
                tz: TimeZone.current.identifier,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                prefs: ["companions": .array(companions.map { .string($0.rawValue) })]
            ))
        } catch {
            Log.api.error("device register failed: \(error.localizedDescription)")
        }
        await refreshEntitlement()
        await alerts.load()
        listenForTransactions()
        await EventQueue.shared.flush(client: api, deviceID: deviceID)
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
            Log.store.error("entitlement failed: \(error.localizedDescription)")
        }
    }

    /// Sends a StoreKit signed transaction to the backend, then reloads the plan.
    func link(signedTransaction jws: String) async {
        do {
            _ = try await api.linkTransaction(deviceID: DeviceIdentity.deviceID, signedTransaction: jws)
        } catch {
            Log.store.error("link transaction failed: \(error.localizedDescription)")
        }
        await refreshEntitlement()
    }

    /// Restore: re-syncs with the App Store and links current entitlements.
    func restorePurchases() async {
        do { try await AppStore.sync() } catch {
            Log.store.error("AppStore.sync failed: \(error.localizedDescription)")
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

    func track(_ name: String, _ props: [String: JSONValue]? = nil) {
        Task { await EventQueue.shared.enqueue(AppEvent(name: name, props: props)) }
    }

    // MARK: - Privacy

    /// Settings → Delete My Data: server device row, local queue, keychain.
    func deleteMyData() async {
        let id = DeviceIdentity.deviceID
        do { try await api.deleteDevice(id: id) } catch {
            Log.api.error("delete device failed: \(error.localizedDescription)")
        }
        await EventQueue.shared.clear()
        KeychainStore.delete(.deviceID)
        KeychainStore.delete(.apnsToken)
        KeychainStore.delete(.apnsEnv)
        defaults.removeObject(forKey: "place")
        defaults.removeObject(forKey: "companions")
        defaults.removeObject(forKey: "filters")
        place = nil
        companions = []
        filters = SpotFilters()
        alerts.reset()
        PaywallSurvey.reset()
        WidgetBridge.clear()
        WidgetCenter.shared.reloadAllTimelines()
        CrowdReportLog.reset()
        entitlement = nil
    }
}
