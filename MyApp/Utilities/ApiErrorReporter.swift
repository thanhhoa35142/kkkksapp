import Foundation

/// What `APIClient` knows about a failed request. Contains no query, body,
/// coordinates or message text.
struct ApiFailure: Sendable {
    let method: String
    /// Path template (`/v1/spots/:id/reports`), never the raw path or query.
    let route: String
    /// HTTP status, 0 for transport and decode failures.
    let status: Int
    let code: String
    let urlError: Int?
    let durationMs: Int
    let requestId: String
    let background: Bool
    let asserted: Bool
}

/// Turns failed requests into `api_error` events for the existing
/// `/v1/events` pipeline. Throttled in memory so a dead network does not
/// flood the queue: one event per (route, code) per 10 minutes, and at most
/// 30 per app session.
actor ApiErrorReporter {
    static let shared = ApiErrorReporter()

    static let sessionLimit = 30
    static let window: TimeInterval = 600

    private var lastSent: [String: Date] = [:]
    private var sentThisSession = 0

    /// Pure throttle decision, separated for tests.
    func shouldReport(route: String, code: String, now: Date = .now) -> Bool {
        guard sentThisSession < Self.sessionLimit else { return false }
        let key = "\(route)|\(code)"
        if let last = lastSent[key], now.timeIntervalSince(last) < Self.window { return false }
        lastSent[key] = now
        sentThisSession += 1
        return true
    }

    func report(_ failure: ApiFailure) async {
        guard shouldReport(route: failure.route, code: failure.code) else { return }
        var props: [String: JSONValue] = [
            "method": .string(failure.method),
            "route": .string(failure.route),
            "status": .number(Double(failure.status)),
            "code": .string(failure.code),
            "durationMs": .number(Double(failure.durationMs)),
            "requestId": .string(failure.requestId),
            "background": .bool(failure.background),
            "asserted": .bool(failure.asserted),
        ]
        if let urlError = failure.urlError { props["urlError"] = .number(Double(urlError)) }
        await EventQueue.shared.enqueue(AppEvent(name: "api_error", props: props))
    }

    /// `/v1/spots/<uuid>/reports` → `/v1/spots/:id/reports`; UUID and
    /// all-digit segments become `:id`, and the share token after
    /// `plan-follows` / `shared-plans` becomes `:token` (it is a capability,
    /// so it must not reach the event store). The query is never an input.
    nonisolated static func routeTemplate(_ path: String) -> String {
        let tokenParents: Set<String> = ["plan-follows", "shared-plans"]
        var previous = ""
        var out = ""
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            let text = String(segment)
            let templated: String
            if tokenParents.contains(previous) {
                templated = ":token"
            } else if UUID(uuidString: text) != nil || text.allSatisfy(\.isASCIIDigit) {
                templated = ":id"
            } else {
                templated = text
            }
            out += "/" + templated
            previous = text
        }
        return out.isEmpty ? "/" : out
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
