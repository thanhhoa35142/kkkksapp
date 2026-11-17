import Foundation

enum AppConfig {
    private static let fallbackBaseURL = URL(string: "http://localhost:8080")!

    /// e.g. `http://localhost:8080` (dev), `https://api.pickhour.app` (prod).
    /// A malformed Info.plist value falls back to localhost rather than crashing.
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
            ?? fallbackBaseURL.absoluteString
        return URL(string: raw) ?? fallbackBaseURL
    }

    /// Host of the share page (`<base>/s/<spotId>`), from Info.plist
    /// `ShareBaseURL`. Must be HTTPS, must match the `applinks:` entry in the
    /// entitlements, and must route `/s/*` and
    /// `/.well-known/apple-app-site-association` to the backend. nil (empty
    /// or not HTTPS) = share the Apple Maps link instead.
    static var shareBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ShareBaseURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    // MARK: Links (owner fills these in before release)
    //
    // Each Settings row appears only when its value is set — never invent
    // a URL or address. App Review requires Privacy Policy and Terms of Use
    // links for auto-renewable subscriptions (Guideline 3.1.2).

    /// Privacy policy on the product site (pickhour-web `/privacy`).
    static let privacyPolicyURL: URL? = URL(string: "https://pickhour.app/privacy")
    /// Terms of Use on the product site (pickhour-web `/terms`); covers
    /// the Plus subscription and refers to Apple's standard EULA.
    static let termsOfUseURL: URL? = URL(string: "https://pickhour.app/terms")
    /// Address for "Send Feedback" (opens Mail via `mailto:`); the site's
    /// support address (pickhour-web `site.email.support`).
    static let feedbackEmail: String? = "support@pickhour.app"

    static var feedbackMailURL: URL? {
        guard let feedbackEmail, !feedbackEmail.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Pickhour feedback")]
        return components.url
    }

    /// Shared API client for the whole app.
    /// UI tests (`-UITestFixtures`) swap in an in-process fixture session.
    static let apiClient = APIClient(baseURL: apiBaseURL, session: UITestFixtures.session ?? .shared)
}
