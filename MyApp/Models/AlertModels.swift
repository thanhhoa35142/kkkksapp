import Foundation

// MARK: - Alert rules
// Server contract: docs/openapi.yaml. A rule targets exactly one of: a
// spotId, an h3Cell + radiusM, or a coarse `area` point + radiusM (the server
// rounds it to 2 decimals and stores only an H3 res-7 cell). `daysMask` bit i = weekday i (0=Sunday).
// `startLocal`/`endLocal` are "HH:MM" in `tz`; windows may cross midnight.

struct AlertRule: Decodable, Identifiable {
    let id: UUID
    let deviceId: UUID
    let spotId: UUID?
    let h3Cell: UInt64?
    /// Cell centre for area rules (3 decimals); null for spot rules.
    let areaCenter: AreaPoint?
    let radiusM: Int?
    let minScore: Int
    let daysMask: Int
    let startLocal: String
    let endLocal: String
    let tz: String
    let enabled: Bool

    var isArea: Bool { spotId == nil }
}

struct AreaPoint: Codable, Equatable, Hashable {
    let lat: Double
    let lon: Double

    /// ~1 km — all the server keeps anyway.
    init(coarse lat: Double, _ lon: Double) {
        self.lat = (lat * 100).rounded() / 100
        self.lon = (lon * 100).rounded() / 100
    }
}

struct AlertRuleList: Decodable {
    let items: [AlertRule]
}

struct AlertRuleRequest: Encodable {
    let deviceId: UUID
    var spotId: UUID?
    var h3Cell: UInt64?
    var area: AreaPoint? = nil
    var radiusM: Int?
    var minScore: Int
    var daysMask: Int
    var startLocal: String
    var endLocal: String
    var tz: String
    var enabled: Bool?
}
