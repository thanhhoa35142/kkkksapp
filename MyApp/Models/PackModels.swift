import CoreLocation
import Foundation

/// `GET /v1/packs` — cities the app has data for.
struct CityPack: Decodable, Identifiable, Hashable {
    let slug: String
    let name: String
    let country: String
    let tz: String
    let center: [Double] // [lon, lat]
    let bbox: [Double]   // [west, south, east, north]
    let activeSpots: Int

    var id: String { slug }

    var coordinate: CLLocationCoordinate2D? {
        guard center.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: center[1], longitude: center[0])
    }

    var countryName: String {
        Locale.current.localizedString(forRegionCode: country) ?? country
    }
}

struct CityPackList: Decodable {
    let items: [CityPack]
}
