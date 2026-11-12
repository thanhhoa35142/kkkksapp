import Foundation

actor EventQueue {
    static let shared = EventQueue()

    private static let maxBatch = 100

    private var pending: [AppEvent] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        load()
    }

    var count: Int { pending.count }

    func enqueue(_ event: AppEvent) {
        pending.append(event)
        persist()
    }

    /// Sends queued events in batches. Stops at the first failure so ordering
    /// is preserved and unsent events stay queued.
    func flush(client: APIClient, deviceID: UUID) async {
        while !pending.isEmpty {
            let batch = Array(pending.prefix(Self.maxBatch))
            do {
                _ = try await client.trackEvents(deviceID: deviceID, events: batch)
                pending.removeFirst(batch.count)
                persist()
            } catch {
                Log.events.error("event flush failed, \(pending.count) still queued: \(error.localizedDescription)")
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        pending = (try? decoder.decode([AppEvent].self, from: data)) ?? []
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
