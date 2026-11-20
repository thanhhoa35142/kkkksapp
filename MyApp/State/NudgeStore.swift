import Foundation
import Observation
import UserNotifications

/// Pure rules for the good-day push home sync — unit-tested in NudgeTests.
enum NudgeSyncRules {
    /// Home is re-sent at least this often while the push is on (keeps the
    /// server's `home_updated_at` fresh; the server may drop stale homes).
    static let refreshInterval: TimeInterval = 7 * 86_400
    /// Never more than one home sync per day.
    static let minInterval: TimeInterval = 86_400

    /// Should the app send `home` now?
    /// - never when the push is off or there is no home yet;
    /// - always when no home was ever sent (first fix after onboarding must
    ///   not wait a day);
    /// - otherwise at most once per day, and only when home changed or the
    ///   last sync is a week old.
    static func shouldSyncHome(enabled: Bool, currentKey: String?, lastKey: String?,
                               lastSync: Date?, now: Date) -> Bool {
        guard enabled, let currentKey else { return false }
        guard let lastKey, let lastSync else { return true }
        let age = now.timeIntervalSince(lastSync)
        if age < 0 { return true }  // clock moved back: the stamp can't be trusted
        if age < minInterval { return false }
        return currentKey != lastKey || age >= refreshInterval
    }
}

/// Good-day push opt-in (`/v1/devices/{id}/nudge`) and home sync.
///
/// The user's choice lives in UserDefaults first; the server call follows.
/// A call that fails (offline, or the device isn't registered yet on a first
/// launch) leaves `needsServerSync` set and is retried by `syncIfNeeded()`
/// on launch and on every foreground.
@MainActor @Observable
final class NudgeStore {
    private(set) var isEnabled: Bool
    private(set) var consent: NudgeConsent?
    /// A server call is in flight (Settings disables the toggle).
    private(set) var isBusy = false
    /// The user has answered the good-day question at least once (on or off).
    private(set) var hasDecided: Bool

    /// Current home, or nil when unknown. Set by `AppState`: the chosen city's
    /// centre, or the last known fix — never a new location request.
    @ObservationIgnored var homeProvider: () -> NudgeHome? = { nil }

    private var api: APIClient { AppConfig.apiClient }
    private let defaults: UserDefaults

    private enum Keys {
        static let enabled = "nudge.enabled"
        static let consent = "nudge.consent"
        static let decided = "nudge.decided"
        static let dirty = "nudge.needsServerSync"
        static let homeKey = "nudge.homeKey"
        static let homeSyncedAt = "nudge.homeSyncedAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        consent = defaults.string(forKey: Keys.consent).flatMap(NudgeConsent.init(rawValue:))
        hasDecided = defaults.bool(forKey: Keys.decided)
    }

    // MARK: Opt in / out

    /// Full permission prompt (it also upgrades a provisional grant), then
    /// an explicit opt-in. Denied: nothing changes.
    func turnOn() async {
        guard await PushManager.shared.requestAuthorization() else { return }
        await PushManager.shared.registerIfAuthorized()
        await enable(explicit: true)
    }

    /// Records the opt-in and tells the server. `explicit` = the user granted
    /// full permission; otherwise the push is provisional (quiet).
    func enable(explicit: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let wasEnabled = isEnabled
        let newConsent: NudgeConsent = explicit ? .explicit : .provisional
        isEnabled = true
        consent = newConsent
        hasDecided = true
        persistChoice()
        if !wasEnabled { track("nudge_opt_in", consent: newConsent) }

        let ok = await pushToServer(consent: newConsent)
        setDirty(!ok)
    }

    /// Opt out: `DELETE /nudge`. The server row is gone, so the next opt-in
    /// sends home again.
    func disable() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        let previous = consent
        let wasEnabled = isEnabled
        isEnabled = false
        consent = nil
        hasDecided = true
        forgetHome()
        persistChoice()
        if wasEnabled { track("nudge_opt_out", consent: previous) }

        let ok = await deleteOnServer()
        setDirty(!ok)
    }

    // MARK: Sync

    /// Launch / foreground: retries a call that failed, then sends `home` when
    /// `NudgeSyncRules` says so. Quiet when off or when home is unknown.
    func syncIfNeeded(now: Date = .now) async {
        guard !isBusy else { return }

        if defaults.bool(forKey: Keys.dirty) {
            isBusy = true
            defer { isBusy = false }
            let ok: Bool
            if isEnabled {
                ok = await pushToServer(consent: consent ?? .provisional, now: now)
            } else {
                ok = await deleteOnServer()
            }
            setDirty(!ok)
            return
        }

        guard isEnabled, let home = homeProvider(),
              NudgeSyncRules.shouldSyncHome(
                enabled: true, currentKey: home.key,
                lastKey: defaults.string(forKey: Keys.homeKey),
                lastSync: defaults.object(forKey: Keys.homeSyncedAt) as? Date, now: now)
        else { return }

        isBusy = true
        defer { isBusy = false }
        let ok = await pushToServer(consent: consent ?? .provisional, home: home, now: now)
        if !ok { setDirty(true) }
    }

    /// Delete My Data: the server row goes with the device (FK cascade).
    func reset() {
        isEnabled = false
        consent = nil
        hasDecided = false
        for key in [Keys.enabled, Keys.consent, Keys.decided, Keys.dirty, Keys.homeKey, Keys.homeSyncedAt] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Server calls

    /// PUT with the current home (when known). Records the home sync only
    /// when `home` was in the request.
    private func pushToServer(consent: NudgeConsent, home: NudgeHome? = nil, now: Date = .now) async -> Bool {
        let home = home ?? homeProvider()
        do {
            try await api.setNudge(deviceID: DeviceIdentity.deviceID, enabled: true,
                                   consent: consent, home: home)
            if let home {
                defaults.set(home.key, forKey: Keys.homeKey)
                defaults.set(now, forKey: Keys.homeSyncedAt)
                Log.api.info("nudge home synced \(home.redactedDescription) (\(home.source.rawValue))")
            }
            return true
        } catch {
            Log.api.error("nudge save failed: \(ErrorSummary.describe(error), privacy: .public)")
            return false
        }
    }

    /// DELETE; a subscription that is already gone counts as done.
    private func deleteOnServer() async -> Bool {
        do {
            try await api.deleteNudge(deviceID: DeviceIdentity.deviceID)
            return true
        } catch let error as APIError where error.code == "not_found" {
            return true
        } catch {
            Log.api.error("nudge delete failed: \(ErrorSummary.describe(error), privacy: .public)")
            return false
        }
    }

    // MARK: Persistence

    private func persistChoice() {
        defaults.set(isEnabled, forKey: Keys.enabled)
        defaults.set(hasDecided, forKey: Keys.decided)
        if let consent { defaults.set(consent.rawValue, forKey: Keys.consent) }
        else { defaults.removeObject(forKey: Keys.consent) }
    }

    private func setDirty(_ value: Bool) {
        defaults.set(value, forKey: Keys.dirty)
    }

    private func forgetHome() {
        defaults.removeObject(forKey: Keys.homeKey)
        defaults.removeObject(forKey: Keys.homeSyncedAt)
    }

    /// Only the consent is a prop — never a place or a coordinate.
    private func track(_ name: String, consent: NudgeConsent?) {
        let props: [String: JSONValue]? = consent.map { (value: NudgeConsent) -> [String: JSONValue] in
            ["consent": JSONValue.string(value.rawValue)]
        }
        Task { await EventQueue.shared.enqueue(AppEvent(name: name, props: props)) }
    }
}
