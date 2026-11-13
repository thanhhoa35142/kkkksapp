import Foundation
import Observation

/// Alert rules for this device (`/v1/alerts`), plus spot names for rows.
/// Free plan: 1 rule — the server answers 403 `plan_limit` past that.
@MainActor @Observable
final class AlertsStore {
    enum SaveResult { case saved, needsPlus, failed(String) }

    /// Mirrors the server's Free limit (shown on the paywall).
    static let freeLimit = 1

    private(set) var rules: [AlertRule] = []
    private(set) var names: [UUID: String] = [:]
    /// Area rules by rule id → place name ("Amsterdam"). The server keeps only
    /// an H3 cell, so the label lives on this device.
    private(set) var areaNames: [UUID: String] = AreaNames.load()
    private(set) var isLoaded = false

    private var api: APIClient { AppConfig.apiClient }

    /// Row / editor title: spot name, or the place an area rule is around.
    func displayName(for rule: AlertRule, summaries: [UUID: SpotSummary]) -> String {
        if let id = rule.spotId {
            return names[id] ?? summaries[id]?.displayName ?? String(localized: "Spot")
        }
        return areaNames[rule.id] ?? String(localized: "Area")
    }

    func rule(for spotID: UUID) -> AlertRule? {
        rules.first { $0.spotId == spotID }
    }

    func load() async {
        do {
            rules = try await api.alerts(deviceID: DeviceIdentity.deviceID)
            isLoaded = true
            await loadNames()
        } catch {
            Log.alerts.error("alerts load failed: \(error.localizedDescription)")
        }
    }

    /// Creates (id nil) or replaces a rule. Asks for notification permission
    /// first — the contextual moment from UI.md — and registers for APNs.
    func save(_ request: AlertRuleRequest, id: UUID?, spotName: String?) async -> SaveResult {
        let granted = await PushManager.shared.requestAuthorization()
        if granted { await PushManager.shared.registerIfAuthorized() }
        do {
            let saved: AlertRule
            if let id {
                saved = try await api.updateAlert(id: id, request)
                rules = rules.map { $0.id == id ? saved : $0 }
            } else {
                saved = try await api.createAlert(request)
                rules.append(saved)
            }
            if let spotID = saved.spotId, let spotName { names[spotID] = spotName }
            if saved.isArea, let spotName {
                areaNames[saved.id] = spotName
                AreaNames.save(areaNames)
            }
            return .saved
        } catch let error as APIError where error.code == "plan_limit" {
            return .needsPlus
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ rule: AlertRule, _ enabled: Bool) async {
        let request = AlertRuleRequest(rule: rule, enabled: enabled)
        _ = await save(request, id: rule.id, spotName: nil)
    }

    func delete(_ rule: AlertRule) async {
        rules.removeAll { $0.id == rule.id }
        if areaNames.removeValue(forKey: rule.id) != nil { AreaNames.save(areaNames) }
        do {
            try await api.deleteAlert(id: rule.id, deviceID: DeviceIdentity.deviceID)
        } catch {
            Log.alerts.error("alert delete failed: \(error.localizedDescription)")
            await load()
        }
    }

    func reset() {
        rules = []
        names = [:]
        areaNames = [:]
        AreaNames.save([:])
        isLoaded = false
    }

    private func loadNames() async {
        let missing = rules.compactMap(\.spotId).filter { names[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let collection = try await api.spots(ids: missing)
            for feature in collection.features {
                names[feature.properties.id] = SpotSummary(feature).displayName
            }
        } catch {
            Log.alerts.error("alert names failed: \(error.localizedDescription)")
        }
    }
}

private enum AreaNames {
    static let key = "alerts.areaNames"

    static func load() -> [UUID: String] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    static func save(_ names: [UUID: String]) {
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: names.map { ($0.uuidString, $1) }), forKey: key)
    }
}

extension AlertRuleRequest {
    init(rule: AlertRule, enabled: Bool) {
        self.init(deviceId: rule.deviceId, spotId: rule.spotId, h3Cell: rule.h3Cell, radiusM: rule.radiusM,
                  minScore: rule.minScore, daysMask: rule.daysMask, startLocal: rule.startLocal,
                  endLocal: rule.endLocal, tz: rule.tz, enabled: enabled)
    }
}

/// `daysMask` bit i = weekday i, 0 = Sunday (matches the backend's Go
/// time.Weekday). Sat+Sun = 65.
enum DaysMask {
    static let everyDay = 127
    static let weekdays = 62  // Mon–Fri
    static let weekends = 65  // Sat + Sun

    static func contains(_ mask: Int, weekday index: Int) -> Bool { mask & (1 << index) != 0 }

    /// "Every day", "Weekends", "Weekdays" or "Mon, Wed, Fri" in locale order.
    static func label(_ mask: Int) -> String {
        switch mask {
        case everyDay: return String(localized: "Every day")
        case weekends: return String(localized: "Weekends")
        case weekdays: return String(localized: "Weekdays")
        default:
            let symbols = Calendar.current.shortWeekdaySymbols
            return orderedIndices.filter { contains(mask, weekday: $0) }
                .map { symbols[$0] }
                .joined(separator: ", ")
        }
    }

    /// Weekday indices (0 = Sunday) starting at the locale's first weekday.
    static var orderedIndices: [Int] {
        let first = Calendar.current.firstWeekday - 1
        return (0..<7).map { (first + $0) % 7 }
    }
}

/// "HH:mm" ↔ hour/minute for the time pickers.
enum LocalTime {
    static func date(from text: String, on day: Date = .now) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0
        let minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func text(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func display(_ text: String) -> String {
        date(from: text).formatted(date: .omitted, time: .shortened)
    }
}
