import Foundation

// MARK: - Alert rules
// Server contract: docs/openapi.yaml. A rule targets EITHER a spotId OR an
// h3Cell + radiusM area — never both. `daysMask` bit i = weekday i (0=Sunday).
// `startLocal`/`endLocal` are "HH:MM" in `tz`; windows may cross midnight.

struct AlertRule: Decodable {
    let id: UUID
    let deviceId: UUID
    let spotId: UUID?
    let h3Cell: UInt64?
    let radiusM: Int?
    let minScore: Int
    let daysMask: Int
    let startLocal: String
    let endLocal: String
    let tz: String
    let enabled: Bool
}

struct AlertRuleList: Decodable {
    let items: [AlertRule]
}

struct AlertRuleRequest: Encodable {
    let deviceId: UUID
    var spotId: UUID?
    var h3Cell: UInt64?
    var radiusM: Int?
    var minScore: Int
    var daysMask: Int
    var startLocal: String
    var endLocal: String
    var tz: String
    var enabled: Bool?
}
