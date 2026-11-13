import Foundation

/// App configuration — values live in Info.plist so dev/staging/prod builds
/// can point at different backends without code changes.
enum AppConfig {
    private static let fallbackBaseURL = URL(string: "http://localhost:8080")!

    /// e.g. `http://localhost:8080` (dev), `https://api.pickhour.app` (prod).
    /// A malformed Info.plist value falls back to localhost rather than crashing.
    static var apiBaseURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
            ?? fallbackBaseURL.absoluteString
        return URL(string: raw) ?? fallbackBaseURL
    }

    /// Shared API client for the whole app.
    /// UI tests (`-UITestFixtures`) swap in an in-process fixture session.
    static let apiClient = APIClient(baseURL: apiBaseURL, session: UITestFixtures.session ?? .shared)
}
