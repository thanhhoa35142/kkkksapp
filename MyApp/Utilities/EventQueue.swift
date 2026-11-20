import Foundation

actor EventQueue {
    static let shared = EventQueue()

    private static let maxBatch = 100
    /// Cap on queued events: a device offline for days stops growing the
    /// file; the oldest are dropped first (the server also caps 5000/day).
    static let maxPending = 1000

    private var pending: [AppEvent] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.fileURL = dir.appendingPathComponent("event-queue.json")
        } else {
            // Application Support is guaranteed on iOS; fall back to tmp rather
            // than crash if the container lookup ever fails.
            self.fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("event-queue.json")
        }
        // Read synchronously from a nonisolated helper: an actor's init can't
        // call its isolated methods (error in Swift 6 mode).
        pending = Self.read(from: self.fileURL)
    }

    var count: Int { pending.count }

    func enqueue(_ event: AppEvent) {
        pending.append(event)
        let overflow = pending.count - Self.maxPending
        if overflow > 0 {
            pending.removeFirst(overflow)
            droppedDuringFlush += overflow
        }
        persist()
    }

    /// Events dropped from the front while a batch was in flight: they were
    /// part of that batch, so they must not be removed a second time.
    private var droppedDuringFlush = 0

    /// The actor is reentrant at the network await: without this, a launch
    /// flush and a going-to-background flush could send the same batch twice
    /// and then each drop it, removing events that were never sent.
    private var isFlushing = false

    /// Sends queued events in batches. Stops at the first failure so ordering
    /// is preserved and unsent events stay queued.
    func flush(client: APIClient, deviceID: UUID) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        while !pending.isEmpty {
            let batch = Array(pending.prefix(Self.maxBatch))
            droppedDuringFlush = 0
            do {
                _ = try await client.trackEvents(deviceID: deviceID, events: batch)
                // Bounded by what is left: `clear()` may have run meanwhile.
                pending.removeFirst(min(pending.count, max(0, batch.count - droppedDuringFlush)))
                persist()
            } catch {
                Log.events.error("event flush failed, \(self.pending.count) still queued: \(ErrorSummary.describe(error), privacy: .public)")
                return
            }
        }
    }

    /// Drops the queue — call on sign-out / account deletion.
    func clear() {
        pending.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private static func read(from url: URL) -> [AppEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AppEvent].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? encoder.encode(pending) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
