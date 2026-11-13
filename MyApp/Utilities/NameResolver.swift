import Foundation

/// Resolves a spot's display name from the API `names` map.
/// Fallback chain: device locale → English → `name` → kind label + city
/// ("Picnic area · Utrecht"). Never shows "—" or an id (UI_SPEC §2).
enum NameResolver {
    /// The device's primary language code, e.g. "nl", "en".
    static var preferredLanguage: String {
        Locale.preferredLanguages.first?
            .split(separator: "-")
            .first
            .map(String.init) ?? "en"
    }

    static func displayName(names: [String: String], fallback name: String?,
                            kind: String = "", city: String? = nil) -> String {
        let lang = preferredLanguage
        if let localized = names[lang] ?? names["en"], !localized.isEmpty { return localized }
        if let name, !name.isEmpty { return name }
        let label = KindStyle.label(kind)
        if let city, !city.isEmpty { return "\(label) · \(city)" }
        return label
    }
}
