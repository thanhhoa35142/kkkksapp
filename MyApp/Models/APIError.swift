import Foundation

/// RFC 7807 problem+json error body returned by the API.
struct APIProblem: Decodable {
    let type: String?
    let code: String
    let title: String
    let status: Int
    let detail: String?
    let instance: String?
    let requestId: String?
}

/// Typed API error — switch on `code`, never on `title`.
struct APIError: Error, LocalizedError {
    let problem: APIProblem

    var errorDescription: String? {
        problem.detail ?? problem.title
    }

    var code: String { problem.code }
    var requestId: String? { problem.requestId }
}
