import CoreLocation
import Foundation

// MARK: - Good-day push (`nudge.goodday`)
// Contract: backend docs/GOOD_DAY_PUSH_SPEC.md §6. Privacy: the server turns
// `home` into a ~5 km² H3 cell and discards the coordinate; the app already
// rounds it to ~1 km before it leaves the device.

/// How the user agreed to the push. "explicit" = tapped Turn On (full
/// permission); "provisional" = quiet delivery, no system prompt.
enum NudgeConsent: String, Codable, Equatable, Sendable {
    case explicit, provisional
}

/// Where the user picnics, coarse. Coordinates are rounded to 2 decimals
/// (~1 km) on creation, so a raw coordinate can't be encoded by accident.
struct NudgeHome: Encodable, Equatable, Sendable {
    /// "location" = last known device fix; "city" = the chosen city's centre.
    enum Source: String, Encodable, Sendable {
        case location, city
    }

    let lat: Double
    let lng: Double
    let source: Source

    init(source: Source, latitude: Double, longitude: Double) {
        self.source = source
        lat = Self.rounded(latitude)
        lng = Self.rounded(longitude)
    }

    init(source: Source, coordinate: CLLocationCoordinate2D) {
        self.init(source: source, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// 2 decimals. `+ 0` turns -0.0 into 0.0 (otherwise JSON gets "-0").
    static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100 + 0
    }

    /// Identity for "did home change": source + rounded point.
    var key: String {
        "\(source.rawValue):" + String(format: "%.2f,%.2f", lat, lng)
    }

    /// For logs (rounded already; still goes through GeoMath, the one rule).
    var redactedDescription: String {
        GeoMath.redactedDescription(of: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }
}

/// `PUT /v1/devices/{id}/nudge` body. `home` and `sendHour` are omitted when nil.
struct NudgeRequest: Encodable, Equatable {
    let enabled: Bool
    let consent: NudgeConsent
    var home: NudgeHome?
    var sendHour: Int?
}

/// 200 body of GET / PUT. The server never exposes the cell id.
struct NudgeSubscription: Decodable, Equatable {
    let enabled: Bool
    let sendHour: Int?
    let homeSet: Bool?
    let homeUpdatedAt: Date?
}
