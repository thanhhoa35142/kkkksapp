import Foundation
import OSLog

/// Unified logging. Coordinates must go through `GeoMath.redactedDescription`
/// — raw user location never enters logs (project privacy rule).
enum Log {
    static let api = Logger(subsystem: "app.pickhour", category: "api")
    static let geo = Logger(subsystem: "app.pickhour", category: "geo")
    static let events = Logger(subsystem: "app.pickhour", category: "events")
    static let alerts = Logger(subsystem: "app.pickhour", category: "alerts")
    static let store = Logger(subsystem: "app.pickhour", category: "storekit")
}
