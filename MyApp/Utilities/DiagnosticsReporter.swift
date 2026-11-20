import Foundation
#if os(iOS) && canImport(MetricKit)
import MetricKit

/// Receives the daily MetricKit payloads and forwards the few numbers worth
/// having to the existing `/v1/events` pipeline (no third-party SDK). Why:
/// the app dying in the background (watchdog, memory, background-task
/// timeout) leaves no trace in our own code, only in these exit counters.
///
/// iOS only: `applicationExitMetrics` and the diagnostics classes are not
/// part of the macOS build we ship. Events are persisted by `EventQueue` and
/// leave with the next flush (bootstrap or going to the background).
///
/// Privacy: counts, enum-like numbers, durations, binary names and offsets.
/// No device identifiers, paths, arguments or user data.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    private var started = false

    /// Registers once; call from app launch.
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    // MARK: - Metrics (exit counters)

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }
            var props: [String: JSONValue] = [
                "appVersion": .string(payload.latestApplicationVersion),
                "from": .string(Self.day(payload.timeStampBegin)),
                "to": .string(Self.day(payload.timeStampEnd)),
            ]
            let foreground = exits.foregroundExitData
            let background = exits.backgroundExitData
            let counts: [(String, Int)] = [
                ("fg_normal", foreground.cumulativeNormalAppExitCount),
                ("fg_abnormal", foreground.cumulativeAbnormalExitCount),
                ("fg_appWatchdog", foreground.cumulativeAppWatchdogExitCount),
                ("fg_memoryResourceLimit", foreground.cumulativeMemoryResourceLimitExitCount),
                ("fg_illegalInstruction", foreground.cumulativeIllegalInstructionExitCount),
                ("fg_badAccess", foreground.cumulativeBadAccessExitCount),
                ("bg_normal", background.cumulativeNormalAppExitCount),
                ("bg_abnormal", background.cumulativeAbnormalExitCount),
                ("bg_appWatchdog", background.cumulativeAppWatchdogExitCount),
                ("bg_memoryResourceLimit", background.cumulativeMemoryResourceLimitExitCount),
                ("bg_memoryPressure", background.cumulativeMemoryPressureExitCount),
                ("bg_cpuResourceLimit", background.cumulativeCPUResourceLimitExitCount),
                ("bg_suspendedWithLockedFile", background.cumulativeSuspendedWithLockedFileExitCount),
                ("bg_illegalInstruction", background.cumulativeIllegalInstructionExitCount),
                ("bg_badAccess", background.cumulativeBadAccessExitCount),
                ("bg_backgroundTaskAssertionTimeout", background.cumulativeBackgroundTaskAssertionTimeoutExitCount),
            ]
            for (key, value) in counts where value > 0 {
                props[key] = .number(Double(value))
            }
            Self.enqueue("diag_exits", props)
        }
    }

    // MARK: - Diagnostics (crash, hang, cpu, disk)

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var props = Self.base(crash.metaData)
                if let value = crash.exceptionType { props["exceptionType"] = .number(value.doubleValue) }
                if let value = crash.exceptionCode { props["exceptionCode"] = .number(value.doubleValue) }
                if let value = crash.signal { props["signal"] = .number(value.doubleValue) }
                if let reason = crash.terminationReason {
                    props["terminationReason"] = .string(Self.truncate(reason, 200))
                }
                if let frames = Self.topFrames(crash.callStackTree.jsonRepresentation(), limit: 8), !frames.isEmpty {
                    props["frames"] = .string(Self.truncate(frames, 800))
                }
                Self.enqueue("diag_crash", props)
            }
            for hang in payload.hangDiagnostics ?? [] {
                var props = Self.base(hang.metaData)
                props["hangDuration"] = .number(hang.hangDuration.converted(to: .seconds).value)
                Self.enqueue("diag_hang", props)
            }
            for cpu in payload.cpuExceptionDiagnostics ?? [] {
                var props = Self.base(cpu.metaData)
                props["totalCPUTime"] = .number(cpu.totalCPUTime.converted(to: .seconds).value)
                props["totalSampledTime"] = .number(cpu.totalSampledTime.converted(to: .seconds).value)
                Self.enqueue("diag_cpu", props)
            }
            for disk in payload.diskWriteExceptionDiagnostics ?? [] {
                var props = Self.base(disk.metaData)
                props["totalWritesMB"] = .number(disk.totalWritesCaused.converted(to: .megabytes).value)
                Self.enqueue("diag_disk", props)
            }
        }
    }

    // MARK: - Helpers

    private static func base(_ meta: MXMetaData) -> [String: JSONValue] {
        ["appVersion": .string(meta.applicationBuildVersion)]
    }

    private static func enqueue(_ name: String, _ props: [String: JSONValue]) {
        Task.detached(priority: .utility) {
            await EventQueue.shared.enqueue(AppEvent(name: name, props: props))
        }
    }

    static func truncate(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }

    /// `yyyy-MM-dd` (UTC): a day is enough to line a payload up with a release.
    private static func day(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// `binary+offset` for the top `limit` frames of the thread that crashed
    /// (`threadAttributed`), crashing frame first, e.g.
    /// `libswiftCore+98 < Pickhour+123456`.
    /// Parsed defensively: any shape surprise returns nil and the event goes
    /// out without frames.
    static func topFrames(_ json: Data, limit: Int) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]], !stacks.isEmpty else { return nil }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks[0]
        guard var frame = (stack["callStackRootFrames"] as? [[String: Any]])?.first else { return nil }
        var chain: [String] = []
        // MetricKit's root frame is the top of the stack (where it crashed);
        // `subFrames` are its callers. A crashed thread is a single chain, so
        // follow the first child; only the top frames are needed.
        for _ in 0..<limit {
            let name = (frame["binaryName"] as? String) ?? "?"
            let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
            chain.append("\(name)+\(offset)")
            guard let next = (frame["subFrames"] as? [[String: Any]])?.first else { break }
            frame = next
        }
        return chain.joined(separator: " < ")
    }
}
#endif
