import Foundation

/// A plain sentence for a failed load, never the system's error text
/// ("The operation couldn't be completed. (NSURLErrorDomain error -1009.)").
enum LoadErrorMessage {
    static func text(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                 .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return String(localized: "You're offline. Check your connection and try again.")
            case .timedOut:
                return String(localized: "This is taking too long. Try again in a moment.")
            default:
                break
            }
        }
        if (error as? APIError)?.code == "rate_limited" {
            return String(localized: "That was quick. Try again in a moment.")
        }
        return String(localized: "Something went wrong on our side. Try again in a moment.")
    }
}
