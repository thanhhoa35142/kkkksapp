import CoreLocation
import Foundation
import MapKit

/// Geo helpers shared by map, API calls and logging.
enum GeoMath {
    /// `GET /v1/spots?bbox=` format: "minLon,minLat,maxLon,maxLat".
    /// Clamps to valid ranges; does not handle the antimeridian (fine for v1 cities).
    static func bboxString(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) -> String {
        let minLon = min(max(minLon, -180), 180)
        let maxLon = min(max(maxLon, -180), 180)
        let minLat = min(max(minLat, -90), 90)
        let maxLat = min(max(maxLat, -90), 90)
        return "\(minLon),\(minLat),\(maxLon),\(maxLat)"
    }

    /// Bbox covering a map region, padded so edge spots aren't clipped.
    static func bbox(for region: MKCoordinateRegion, padding: Double = 0.02) -> String {
        let dLat = region.span.latitudeDelta / 2 + padding
        let dLon = region.span.longitudeDelta / 2 + padding
        return bboxString(
            minLon: region.center.longitude - dLon,
            minLat: region.center.latitude - dLat,
            maxLon: region.center.longitude + dLon,
            maxLat: region.center.latitude + dLat
        )
    }
}

extension CLLocationCoordinate2D {
    /// Great-circle distance in meters.
    func distanceMeters(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

extension GeoMath {
    /// Coordinate safe for logs — rounded to ~1.1 km grid. Spec rule: never
    /// log raw user coordinates.
    static func redactedDescription(of coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude)
    }
}
