import Foundation

/// Resolves a spot's display name from the API `names` map.
/// Fallback chain: device locale → English → `name` → id prefix.
enum NameResolver {
    /// The device's primary language code, e.g. "nl", "en".
    static var preferredLanguage: String {
        Locale.preferredLanguages.first?
            .split(separator: "-")
            .first
            .map(String.init) ?? "en"
    }

    static func displayName(names: [String: String], fallback name: String?) -> String {
        let lang = preferredLanguage
        return names[lang] ?? names["en"] ?? name ?? "—"
    }
}
