import Foundation

/// A short, privacy-safe description of any error, for logs and the
/// `api_error` event. `localizedDescription` is unusable there: OSLog hides
/// interpolated strings (`<private>`) and system messages can embed URLs
/// or query strings. This keeps only codes and type names, never messages.
enum ErrorSummary {
    static func describe(_ error: Error) -> String {
        if let api = error as? APIError {
            return "APIError \(api.code) status=\(api.problem.status)"
        }
        if let url = error as? URLError {
            return "URLError \(url.code.rawValue) \(urlErrorName(url.code))"
        }
        if let decoding = error as? DecodingError {
            return describe(decoding)
        }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// Short stable name for the codes that matter in the field; others
    /// report only the raw value.
    static func urlErrorName(_ code: URLError.Code) -> String {
        switch code {
        case .timedOut: return "timedOut"
        case .networkConnectionLost: return "networkConnectionLost"
        case .notConnectedToInternet: return "notConnectedToInternet"
        case .cannotFindHost: return "cannotFindHost"
        case .cannotConnectToHost: return "cannotConnectToHost"
        case .dnsLookupFailed: return "dnsLookupFailed"
        case .cancelled: return "cancelled"
        case .secureConnectionFailed: return "secureConnectionFailed"
        case .badServerResponse: return "badServerResponse"
        case .dataNotAllowed: return "dataNotAllowed"
        case .internationalRoamingOff: return "roamingOff"
        case .backgroundSessionWasDisconnected: return "backgroundSessionWasDisconnected"
        default: return "other"
        }
    }

    /// Case name plus the key path only: the values being decoded are never
    /// included.
    private static func describe(_ error: DecodingError) -> String {
        let name: String
        let path: [CodingKey]
        switch error {
        case .typeMismatch(_, let context): name = "typeMismatch"; path = context.codingPath
        case .valueNotFound(_, let context): name = "valueNotFound"; path = context.codingPath
        case .keyNotFound(_, let context): name = "keyNotFound"; path = context.codingPath
        case .dataCorrupted(let context): name = "dataCorrupted"; path = context.codingPath
        @unknown default: name = "unknown"; path = []
        }
        let keys = path.map { $0.intValue != nil ? "[]" : $0.stringValue }.joined(separator: ".")
        return "DecodingError \(name) \(keys)"
    }
}
