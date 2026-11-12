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

    var coordinate: CLLocationCoordinate2D? {
        guard coordinates.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
    }
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
