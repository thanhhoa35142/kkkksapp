import Foundation

// MARK: - App config (force update)

/// `GET /v1/app/config`: the server's iOS version policy and where this
/// build stands against it (from the `X-Client-Version` header).
struct AppConfigResponse: Decodable {
    let minVersion: String?
    let latestVersion: String?
    let storeUrl: String?
    let status: AppVersionStatus
}

enum AppVersionStatus: String, Decodable {
    case ok
    case updateAvailable = "update_available"
    case updateRequired = "update_required"
    case unknown

    /// A status added server-side later must not break decoding.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppVersionStatus(rawValue: raw) ?? .unknown
    }
}

/// What the app shows about its own version.
enum AppUpdateState: Equatable {
    case none
    /// Soft prompt, once per launch; the app keeps working.
    case available(storeURL: URL?)
    /// The server answers `426 upgrade_required`: nothing else works until
    /// the user updates.
    case required(storeURL: URL?)
}

/// Bridge from the `APIClient` actor to the UI: any response with
/// `upgrade_required` (whichever request hit it) flips the app into the
/// update-required screen. Set by `AppState`.
@MainActor
enum AppUpdateSignal {
    static var onUpgradeRequired: ((URL?) -> Void)?
}

extension APIClient {
    func appConfig() async throws -> AppConfigResponse {
        try await get("/v1/app/config", enveloped: true)
    }

    /// Called from `validate` for every failed response.
    static func signalUpgradeIfNeeded(status: Int, problem: APIProblem?) {
        guard status == 426 || problem?.code == "upgrade_required" else { return }
        let storeURL: URL?
        if case .string(let raw)? = problem?.params?["storeUrl"] {
            storeURL = URL(string: raw)
        } else {
            storeURL = nil
        }
        Task { @MainActor in AppUpdateSignal.onUpgradeRequired?(storeURL) }
    }
}
