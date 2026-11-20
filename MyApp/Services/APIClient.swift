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

    /// The app's session. `URLSession.shared` waits 60 s per request, which
    /// leaves a user (and, for asserted POSTs, every request queued behind
    /// them) staring at a stuck screen. 20 s per request is plenty for these
    /// small JSON calls; 60 s caps the whole transfer.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    init(baseURL: URL, session: URLSession = APIClient.makeSession()) {
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

    /// Fresh per request; the one sent is read back from the request when a
    /// failure is reported, so the event matches the server's log line.
    private func newRequestID() -> String { UUID().uuidString }

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
        request.setValue(newRequestID(), forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        Self.applyDeviceHeaders(to: &request)

        return try await transact(request) { try self.decode($0, enveloped: enveloped) }
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
        request.setValue(newRequestID(), forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        Self.applyDeviceHeaders(to: &request)
        request.httpBody = body

        guard asserted else { return try await execute(request, asserted: false) }
        // The lock spans the network call on purpose: the server rejects an
        // App Attest counter lower than the last one it accepted, so a signed
        // request must reach it before the next one is signed. That is also
        // why the session's request timeout is short: one stuck request holds
        // everything queued behind it.
        await Self.assertionLock.lock()
        do {
            // Signs the path as sent (what the server reads from the URL).
            if let assertion = await AppAttestor.assertion(
                method: method.rawValue, path: request.url?.path ?? path, body: body) {
                request.setValue(assertion, forHTTPHeaderField: "X-App-Assertion")
            }
            let result: T = try await execute(request, asserted: true)
            await Self.assertionLock.unlock()
            return result
        } catch {
            await Self.assertionLock.unlock()
            throw error
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest, asserted: Bool) async throws -> T {
        try await transact(request, asserted: asserted) { try self.decode($0, enveloped: true) }
    }

    /// The single choke point for every request: runs it under a background
    /// task assertion (so leaving the app mid-request doesn't kill it),
    /// validates, parses, and reports failures as `api_error` events.
    private func transact<T>(
        _ request: URLRequest, asserted: Bool = false, _ parse: (Data) throws -> T
    ) async throws -> T {
        let started = ContinuousClock.now
        do {
            let session = self.session
            let (data, response) = try await withBackgroundTask(name: "app.pickhour.api") {
                try await session.data(for: request)
            }
            try validate(response: response, data: data)
            return try parse(data)
        } catch {
            reportFailure(error, request: request, started: started, asserted: asserted)
            throw error
        }
    }

    /// Fire-and-forget: reporting must never delay or change the outcome of
    /// the request (nor hold the assertion lock). Skips `/v1/events` itself
    /// (loop), cancellations, and answers the app expects (404 `not_found`
    /// on digest/nudge, 426 handled by the update screen).
    private func reportFailure(_ error: Error, request: URLRequest, started: ContinuousClock.Instant, asserted: Bool) {
        guard !UITestFixtures.isActive, !(error is CancellationError),
              let url = request.url, url.path != "/v1/events" else { return }
        var status = 0
        var urlErrorCode: Int?
        let code: String
        if let api = error as? APIError {
            status = api.problem.status
            code = api.code
            if (status == 404 && code == "not_found") || status == 426 || code == "upgrade_required" { return }
        } else if let urlError = error as? URLError {
            if urlError.code == .cancelled { return }
            code = ErrorSummary.urlErrorName(urlError.code)
            urlErrorCode = urlError.code.rawValue
        } else if error is DecodingError {
            code = "decode_error"
        } else {
            code = "other"
        }
        let elapsed = started.duration(to: .now)
        let durationMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let method = request.httpMethod ?? "GET"
        let route = ApiErrorReporter.routeTemplate(url.path)
        let requestId = request.value(forHTTPHeaderField: "X-Request-ID") ?? ""
        Task.detached(priority: .utility) {
            let background = await MainActor.run { AppActivity.isBackground }
            await ApiErrorReporter.shared.report(ApiFailure(
                method: method, route: route, status: status, code: code, urlError: urlErrorCode,
                durationMs: durationMs, requestId: requestId, background: background, asserted: asserted))
        }
    }

    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        var request = URLRequest(url: try url(for: path, query: query))
        request.httpMethod = HTTPMethod.delete.rawValue
        request.setValue(newRequestID(), forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.clientHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        Self.applyDeviceHeaders(to: &request)

        try await transact(request) { _ in () }
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
