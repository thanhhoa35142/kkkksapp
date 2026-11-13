import CoreLocation
import Foundation

// MARK: - Map (GeoJSON)

struct SpotFeatureCollection: Decodable {
    let type: String
    let features: [SpotFeature]
}

struct SpotFeature: Decodable {
    struct Geometry: Decodable {
        let type: String
        /// GeoJSON order: [longitude, latitude]. Nil when malformed (<2 elements).
        let coordinates: [Double]

        var coordinate: CLLocationCoordinate2D? {
            guard coordinates.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        }
    }

    struct Properties: Decodable {
        let id: UUID
        let kind: String
        let name: String?
        let names: [String: String]
        let country: String
        let city: String?
        let tz: String
        let lastVerifiedAt: Date?
        let when: Date
        let score: ScoreSnapshot?
        /// Hourly scores from `from` — present only when requested with `hours=`.
        let scores: [HourScore]?
        /// Simplified park outline — present only with `include=area`.
        let area: JSONValue?
    }

    let type: String
    let geometry: Geometry
    let properties: Properties
}

// MARK: - Spot detail

struct SpotDetail: Decodable {
    struct Amenity: Decodable {
        let type: String
        let distanceM: Int
        let source: String
    }

    struct Source: Decodable {
        let source: String
        let sourceId: String
        let version: Int?
        let importedAt: Date
    }

    let id: UUID
    let kind: String
    let name: String?
    let names: [String: String]
    /// [longitude, latitude]
    let coordinates: [Double]
    let area: JSONValue? // GeoJSON MultiPolygon, decoded lazily if needed
    let country: String
    let city: String?
    let tz: String
    let lastVerifiedAt: Date?
    let amenities: [Amenity]
    let sources: [Source]
    /// "weatherkit" | "openmeteo" | nil — drives the weather attribution line.
    let weatherSource: String?

    var coordinate: CLLocationCoordinate2D? {
        guard coordinates.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
    }
}

/// One hour of a viewport time-lapse (`GET /v1/spots?...&hours=`).
struct HourScore: Decodable {
    let tsHour: Date
    let score: Int
    let capReason: String?
}

struct ForecastPoint: Decodable {
    struct Components: Decodable {
        let weather: Int?
        let crowd: Int?
        let amenity: Int?
        let shade: Int?
        let fresh: Int?
    }

    let tsHour: Date
    let score: Int
    let components: Components
    let capReason: String?
    let reasons: [Reason]
    let confidence: Int
}
