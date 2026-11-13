import Foundation

/// What the app hands the widget through the shared App Group. Compiled
/// into both the app and the PickhourWidget extension (Shared/ folder).
/// Only a coarse point (2 decimals ≈ 1 km) — never the precise location.
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
    }

    private static let key = "widget.snapshot"

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
    }

    /// `pickhour://spot/<id>` — same scheme the app handles in RootView.
    static func spotURL(_ id: UUID) -> URL {
        URL(string: "pickhour://spot/\(id.uuidString)")!
    }
}
