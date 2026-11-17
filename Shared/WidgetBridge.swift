import Foundation


enum WidgetBridge {
    /// Must match `com.apple.security.application-groups` in the app's and
    /// the widget's entitlements (rename together with the bundle ID).
    static let appGroup = "group.com.example.MyApp"
    static let bestNowKind = "BestNowWidget"

    struct Snapshot: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var placeName: String
        var apiBaseURL: String
        var usesMetric: Bool
        /// Free widgets stop at tomorrow, like the app. Optional so snapshots
        /// saved by older builds still decode (nil = Free).
        var isPlus: Bool? = nil
    }

    private static let key = "widget.snapshot"
    private static let plansKey = "widget.plans"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ snapshot: Snapshot) {
        var coarse = snapshot
        coarse.latitude = (snapshot.latitude * 100).rounded() / 100
        coarse.longitude = (snapshot.longitude * 100).rounded() / 100
        guard let data = try? JSONEncoder().encode(coarse) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> Snapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
        defaults?.removeObject(forKey: plansKey)
    }

    // MARK: Plans

    /// Upcoming picnic plans (not ended), soonest first, at most `maxPlans`.
    /// Returns true when the stored list changed.
    static let maxPlans = 3

    @discardableResult
    static func savePlans(_ plans: [PlanSnapshot]) -> Bool {
        let list = Array(plans.sorted { $0.start < $1.start }.prefix(maxPlans))
        guard list != loadPlans() else { return false }
        if list.isEmpty {
            defaults?.removeObject(forKey: plansKey)
        } else if let data = try? JSONEncoder().encode(list) {
            defaults?.set(data, forKey: plansKey)
        }
        return true
    }

    static func loadPlans() -> [PlanSnapshot] {
        guard let data = defaults?.data(forKey: plansKey),
              let list = try? JSONDecoder().decode([PlanSnapshot].self, from: data) else { return [] }
        return list
    }

    /// `pickhour://spot/<id>` — same scheme the app handles in RootView.
    static func spotURL(_ id: UUID) -> URL {
        URL(string: "pickhour://spot/\(id.uuidString)")!
    }

    /// Widget tap: the spot at an hour, tagged `src=widget` for the
    /// `widget_opened` event.
    static func spotURL(_ id: UUID, at hour: Date?) -> URL {
        PlanLink.url(spotURL(id), at: hour, source: PlanLink.widgetSource)
    }

    /// Widget tap with no spot (empty states): opens the app, tagged.
    static var appURL: URL {
        URL(string: "pickhour://open?src=widget")!
    }
}
