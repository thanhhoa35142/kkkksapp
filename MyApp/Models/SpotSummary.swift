import CoreLocation
import Foundation

/// What a list row, map pin or detail header needs — built from any API
/// shape (recommendation item, map feature, saved favorite) so every screen
/// renders spots the same way.
struct SpotSummary: Identifiable {
    let id: UUID
    let kind: String
    let name: String?
    let names: [String: String]
    let city: String?
    let tz: String
    let latitude: Double?
    let longitude: Double?
    var distanceM: Double?
    var score: ScoreSnapshot?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    var displayName: String {
        NameResolver.displayName(names: names, fallback: name, kind: kind, city: city)
    }

    /// "Park · 1.2 km" (distance only when known).
    var subtitle: String {
        var parts = [KindStyle.label(kind)]
        if let distanceM { parts.append(Format.distance(meters: distanceM)) }
        else if let city, name != nil { parts.append(city) }
        return parts.joined(separator: " · ")
    }

    /// First two reasons, e.g. "Clear skies, 21° · Usually quiet at this hour".
    var reasonLine: String? {
        guard let reasons = score?.reasons, !reasons.isEmpty else { return nil }
        let known = reasons.filter { ReasonLocalizer.isKnown($0.code) }
        guard !known.isEmpty else { return nil }
        return known.prefix(2).map(ReasonLocalizer.text(for:)).joined(separator: " · ")
    }
}

extension SpotSummary {
    init(_ item: RecommendationList.Item) {
        self.init(id: item.id, kind: item.kind, name: item.name, names: item.names,
                  city: item.city, tz: item.tz,
                  latitude: item.coordinate?.latitude, longitude: item.coordinate?.longitude,
                  distanceM: item.distanceM, score: item.score)
    }

    init(_ feature: SpotFeature) {
        let p = feature.properties
        self.init(id: p.id, kind: p.kind, name: p.name, names: p.names,
                  city: p.city, tz: p.tz,
                  latitude: feature.geometry.coordinate?.latitude,
                  longitude: feature.geometry.coordinate?.longitude,
                  distanceM: nil, score: p.score)
    }

    init(_ favorite: FavoriteSpot, score: ScoreSnapshot? = nil) {
        self.init(id: favorite.spotID, kind: favorite.kind, name: favorite.name, names: [:],
                  city: favorite.city, tz: favorite.tz,
                  latitude: favorite.latitude, longitude: favorite.longitude,
                  distanceM: nil, score: score)
    }
}

extension SpotSummary {
    /// Apple Maps link — what Share, drag and drop and Copy hand to other apps.
    var mapsURL: URL? {
        guard let latitude, let longitude else { return nil }
        return SpotLink.mapsURL(name: displayName, latitude: latitude, longitude: longitude)
    }
}

enum SpotLink {
    static func mapsURL(name: String, latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return components?.url
    }

    /// `pickhour://spot/<id>` — opens Spot Detail (widget, Handoff).
    static func appURL(spotID: UUID) -> URL {
        URL(string: "pickhour://spot/\(spotID.uuidString)")!
    }

    /// `<ShareBaseURL>/s/<id>` — the Pickhour share page. It is a universal
    /// link: opens the app when installed, a web page otherwise. nil when no
    /// share host is configured (callers fall back to the Apple Maps link).
    static func shareURL(spotID: UUID, base: URL? = AppConfig.shareBaseURL) -> URL? {
        base?.appendingPathComponent("s").appendingPathComponent(spotID.uuidString.lowercased())
    }

    /// Accepts `pickhour://spot/<id>` and the share page `https://<host>/s/<id>`.
    static func spotID(from url: URL, shareBase: URL? = AppConfig.shareBaseURL) -> UUID? {
        if url.scheme == "pickhour", url.host == "spot" {
            return UUID(uuidString: url.lastPathComponent)
        }
        if let shareHost = shareBase?.host, url.scheme == "https",
           url.host?.lowercased() == shareHost.lowercased() {
            let parts = url.pathComponents // ["/", "s", "<id>"]
            if parts.count == 3, parts[1] == "s" { return UUID(uuidString: parts[2]) }
        }
        return nil
    }
}
