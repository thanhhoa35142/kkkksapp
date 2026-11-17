import Foundation

struct DeviceRegisterRequest: Encodable {
    let id: UUID
    var apnsToken: String?
    var apnsEnv: String? // "sandbox" | "production"
    var locale: String?
    var tz: String?
    var appVersion: String?
    var prefs: [String: JSONValue]?
}

struct DeviceIDResponse: Decodable {
    let id: UUID
    /// Present only when the server issued a credential by this call —
    /// store it in the Keychain immediately.
    let deviceSecret: String?
}
