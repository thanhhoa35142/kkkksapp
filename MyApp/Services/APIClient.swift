import Foundation

actor APIClient {
    enum HTTPMethod: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    let baseURL: URL
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder


    static let clientHeaders: [String: String] = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return [
            "X-Client": "pickhour-ios",
            "X-Client-Version": "\(version)+\(build)",
            "X-Client-OS": "ios \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ","),
        ]
    }()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            return try APIClient.parseDate(string)
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Property names are already camelCase matching the API contract.
        self.encoder = encoder
    }

    // MARK: - Plumbing

    var requestID: String { UUID().uuidString }

    private func url(for path: String, query: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw APIError(problem: APIProblem(
                type: nil, code: "invalid_url", title: "Invalid request URL",
                status: 0, detail: path, instance: nil, requestId: nil
            ))
        }
        return url
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], enveloped: Bool) async throws -> T {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decode(data, enveloped: enveloped)
    }

    func send<T: Decodable>(_ method: HTTPMethod, _ path: String, body: Encodable) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try encoder.encode(AnyEncodable(body))

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decode(data, enveloped: true)
    }

    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = HTTPMethod.delete.rawValue
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    func decode<T: Decodable>(_ data: Data, enveloped: Bool) throws -> T {
        if enveloped {
            return try decoder.decode(Envelope<T>.self, from: data).data
        }
        return try decoder.decode(T.self, from: data)
    }

    func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(problem: APIProblem(type: nil, code: "transport_error", title: "No HTTP response", status: 0, detail: nil, instance: nil, requestId: nil))
        }
        guard (200..<300).contains(http.statusCode) else {
            if let problem = try? decoder.decode(APIProblem.self, from: data) {
                throw APIError(problem: problem)
            }
            throw APIError(problem: APIProblem(
                type: nil, code: "http_\(http.statusCode)", title: "HTTP \(http.statusCode)",
                status: http.statusCode, detail: nil, instance: nil, requestId: nil
            ))
        }
    }

    private static func parseDate(_ string: String) throws -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad date: \(string)"))
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeClosure = { try wrapped.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
