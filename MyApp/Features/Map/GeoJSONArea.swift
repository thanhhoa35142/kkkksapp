import CoreLocation
import MapKit

/// GeoJSON (Multi)Polygon → MapKit / SwiftUI shapes. Coordinates are
/// `[lon, lat]`; rings after the first are holes.
enum GeoJSONArea {
    /// Polygons as rings: `[polygon][ring][coordinate]`.
    static func polygons(_ value: JSONValue?) -> [[[CLLocationCoordinate2D]]] {
        guard case .object(let object)? = value,
              case .string(let type)? = object["type"],
              case .array(let coordinates)? = object["coordinates"] else { return [] }
        switch type {
        case "Polygon":
            return [rings(coordinates)].filter { !$0.isEmpty }
        case "MultiPolygon":
            return coordinates.compactMap { polygon -> [[CLLocationCoordinate2D]]? in
                guard case .array(let r) = polygon else { return nil }
                let parsed = rings(r)
                return parsed.isEmpty ? nil : parsed
            }
        default:
            return []
        }
    }

    /// Outer rings only — for SwiftUI `MapPolygon` in the detail header.
    static func outerRings(_ value: JSONValue?) -> [[CLLocationCoordinate2D]] {
        polygons(value).compactMap(\.first)
    }

    static func multiPolygon(_ value: JSONValue?) -> MKMultiPolygon? {
        let shapes = polygons(value).compactMap { rings -> MKPolygon? in
            guard let outer = rings.first, outer.count >= 3 else { return nil }
            let holes = rings.dropFirst().filter { $0.count >= 3 }.map {
                MKPolygon(coordinates: $0, count: $0.count)
            }
            return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: holes)
        }
        return shapes.isEmpty ? nil : MKMultiPolygon(shapes)
    }

    private static func rings(_ values: [JSONValue]) -> [[CLLocationCoordinate2D]] {
        values.compactMap { ring -> [CLLocationCoordinate2D]? in
            guard case .array(let points) = ring else { return nil }
            let coords = points.compactMap { point -> CLLocationCoordinate2D? in
                guard case .array(let pair) = point, pair.count >= 2,
                      case .number(let lon) = pair[0], case .number(let lat) = pair[1] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            return coords.count >= 3 ? coords : nil
        }
    }
}
