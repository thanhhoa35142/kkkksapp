import CoreLocation
import Foundation

struct RecommendationList: Decodable {
    struct Item: Decodable {
        let id: UUID
        let kind: String
        let name: String?
        let names: [String: String]
        let coordinates: [Double]
        let country: String
        let city: String?
        let tz: String
        let lastVerifiedAt: Date?
        let distanceM: Double
        let score: ScoreSnapshot?

        var coordinate: CLLocationCoordinate2D? {
            guard coordinates.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: coordinates[1], longitude: coordinates[0])
        }
    }

    let when: Date
    let items: [Item]
}
