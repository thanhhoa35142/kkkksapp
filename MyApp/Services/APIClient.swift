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

    /// Device-scoped calls authenticate with the per-device secret issued at
    /// registration. Sent on every request: public read endpoints ignore it,
    /// device endpoints require it. No secret yet (first launch, before
    /// `POST /v1/devices` returns one) → only the ID goes out.
    private static func applyDeviceHeaders(to request: inout URLRequest) {
        request.setValue(DeviceIdentity.deviceID.uuidString, forHTTPHeaderField: "X-Device-ID")
        if let secret = DeviceIdentity.deviceSecret {
            request.setValue(secret, forHTTPHeaderField: "X-Device-Token")
        }
    }

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
        Self.applyDeviceHeaders(to: &request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decode(data, enveloped: enveloped)
    }

    /// Asserted requests go out one at a time across all clients: the server
    /// refuses an App Attest counter lower than the last one it accepted, so
    /// requests must arrive in the order they were signed.
    private static let assertionLock = AsyncLock()

    func send<T: Decodable>(_ method: HTTPMethod, _ path: String, body: Encodable) async throws -> T {
        // Encoded once: the assertion signs exactly the bytes that are sent.
        let bodyData = try encoder.encode(AnyEncodable(body))
        guard AppAssertionRoutes.covers(method, path) else {
            return try await perform(method, path, body: bodyData, asserted: false)
        }
        do {
            return try await perform(method, path, body: bodyData, asserted: true)
        } catch let error as APIError where error.code == "attest_required" {
            // The route enforces App Attest and the server doesn't know our
            // key (reinstall, deleted data): re-attest, then retry once.
            guard await AppAttestor.attestIfNeeded(api: self, force: true) else { throw error }
            return try await perform(method, path, body: bodyData, asserted: true)
        }
    }

    private func perform<T: Decodable>(_ method: HTTPMethod, _ path: String, body: Data, asserted: Bool) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method.rawValue
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        Self.applyDeviceHeaders(to: &request)
        request.httpBody = body

        guard asserted else { return try await execute(request) }
        await Self.assertionLock.lock()
        do {
            // Signs the path as sent (what the server reads from the URL).
            if let assertion = await AppAttestor.assertion(
                method: method.rawValue, path: request.url?.path ?? path, body: body) {
                request.setValue(assertion, forHTTPHeaderField: "X-App-Assertion")
            }
            let result: T = try await execute(request)
            await Self.assertionLock.unlock()
            return result
        } catch {
            await Self.assertionLock.unlock()
            throw error
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
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
        Self.applyDeviceHeaders(to: &request)

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
            let problem = try? decoder.decode(APIProblem.self, from: data)
            Self.signalUpgradeIfNeeded(status: http.statusCode, problem: problem)
            if let problem {
                throw APIError(problem: problem)
            }
            throw APIError(problem: APIProblem(
                type: nil, code: "http_\(http.statusCode)", title: "HTTP \(http.statusCode)",
                status: http.statusCode, detail: nil, instance: nil, requestId: nil
            ))
        }
    }

    /// RFC 3339 with or without a fraction. Go sends RFC3339Nano (0–9
    /// fractional digits, trailing zeros trimmed); the fraction is brought to
    /// exactly 3 digits first so the formatter never sees more than it is
    /// documented to accept. Pure — unit-tested.
    static func parseDate(_ string: String) throws -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: normalizedFraction(string)) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad date: \(string)"))
    }

    /// `…:SS.<digits><zone>` → `…:SS.ddd<zone>` (truncated or zero-padded).
    /// Strings without a fraction are returned unchanged (plain fallback).
    static func normalizedFraction(_ string: String) -> String {
        guard let t = string.firstIndex(where: { $0 == "T" || $0 == "t" }),
              let dot = string[t...].firstIndex(of: ".") else { return string }
        let afterDot = string.index(after: dot)
        let zone = string[afterDot...].firstIndex(where: { !$0.isASCII || !$0.isNumber }) ?? string.endIndex
        let digits = string[afterDot..<zone]
        let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return String(string[...dot]) + millis + String(string[zone...])
    }
}

/// Routes the backend checks `X-App-Assertion` on (its App Attest route
/// groups: devices, reports, entitlement, plans). Public GETs never carry one.
enum AppAssertionRoutes {
    static func covers(_ method: APIClient.HTTPMethod, _ path: String) -> Bool {
        guard method == .post else { return false }
        switch path {
        case "/v1/devices", "/v1/scores/feedback", "/v1/entitlement/link", "/v1/plans":
            return true
        default:
            if path.hasPrefix("/v1/plan-follows/") { return true }
            return path.hasPrefix("/v1/spots/")
                && (path.hasSuffix("/reports") || path.hasSuffix("/crowd-reports"))
        }
    }
}

/// FIFO async mutex (no thread is blocked while waiting).
actor AsyncLock {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        guard locked else {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeClosure = { try wrapped.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
