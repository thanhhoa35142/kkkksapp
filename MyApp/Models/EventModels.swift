import Foundation

// MARK: - Product events
// Privacy contract: never put location or PII in `props`. Event names must
// match `^[a-z][a-z0-9_]{0,63}$`. Batches are 1–100 events; the server caps
// at 5000 events/device/day.

struct AppEvent: Codable {
    let name: String
    var props: [String: JSONValue]?
}

struct TrackEventsRequest: Encodable {
    let deviceId: UUID
    let events: [AppEvent]
}

struct TrackEventsResponse: Decodable {
    let status: String // "accepted"
    let count: Int
}
