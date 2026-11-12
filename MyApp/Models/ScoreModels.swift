import Foundation

struct Reason: Decodable {
    let code: String
    let params: [String: JSONValue]?
}

struct ScoreSnapshot: Decodable {
    let score: Int
    let confidence: Int
    let capReason: String?
    let reasons: [Reason]
    let computedAt: Date?
}
