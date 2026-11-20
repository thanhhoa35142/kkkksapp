import Foundation

/// The 7-day forecast per spot, shared by the week plan, the plan statuses
/// and spot detail. Without it the Saved tab fetched up to 10 forecasts
/// (+1 per planned spot) on every appearance, and the server limits reads
/// per IP — people on one carrier NAT or office Wi-Fi share that budget.
///
/// Scores change hourly at most, so an answer is reused for 10 minutes, and
/// concurrent asks for the same spot share one request. Failures are not
/// cached: the next ask tries again.
actor ForecastCache {
    static let shared = ForecastCache()

    static let maxAge: TimeInterval = 600
    /// Bounds memory; Saved holds at most 10 spots plus a few plans/details.
    static let capacity = 40

    private var entries: [UUID: (fetchedAt: Date, points: [ForecastPoint])] = [:]
    private var inFlight: [UUID: Task<[ForecastPoint], Error>] = [:]
    private let fetch: @Sendable (UUID) async throws -> [ForecastPoint]

    init(fetch: @escaping @Sendable (UUID) async throws -> [ForecastPoint] = { id in
        try await AppConfig.apiClient.forecast(spotID: id)
    }) {
        self.fetch = fetch
    }

    func forecast(spotID: UUID, now: Date = .now) async throws -> [ForecastPoint] {
        if let entry = entries[spotID], now.timeIntervalSince(entry.fetchedAt) < Self.maxAge {
            return entry.points
        }
        if let running = inFlight[spotID] {
            return try await running.value
        }
        let fetch = self.fetch
        let task = Task { try await fetch(spotID) }
        inFlight[spotID] = task
        defer { inFlight[spotID] = nil }
        let points = try await task.value
        store(points, for: spotID, at: .now)
        return points
    }

    private func store(_ points: [ForecastPoint], for spotID: UUID, at date: Date) {
        entries[spotID] = (date, points)
        guard entries.count > Self.capacity else { return }
        // Oldest first out.
        let excess = entries.count - Self.capacity
        for key in entries.sorted(by: { $0.value.fetchedAt < $1.value.fetchedAt }).prefix(excess).map(\.key) {
            entries[key] = nil
        }
    }
}
