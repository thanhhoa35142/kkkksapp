import CoreLocation
import SwiftUI

/// S9 · "How busy is it right now?" — shown in Spot Detail only when the
/// user is at the spot. Proximity is checked on device; the server never
/// receives coordinates (API.md crowd-reports). Never asks for location
/// permission itself: no permission → the section just doesn't appear.
/// The parent decides `isNear` (`CrowdProximity.check`) from a view that
/// always exists — a `.task` here would never run while the section is empty.
struct CrowdReportSection: View {
    let spotID: UUID

    @Environment(AppState.self) private var app
    @State private var sentLevel: Level?
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = 0

    enum Level: Int, CaseIterable, Identifiable {
        case quiet = 1, moderate = 2, busy = 3
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .quiet: String(localized: "Quiet")
            case .moderate: String(localized: "Some people")
            case .busy: String(localized: "Busy")
            }
        }
    }

    var body: some View {
        Section {
            if let sentLevel {
                Label("Thanks — you said \(sentLevel.title.lowercased()).", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(Level.allCases) { level in
                        Button {
                            Task { await send(level) }
                        } label: {
                            Text(level.title).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSending)
                    }
                }
                .controlSize(.large)
                .padding(.vertical, 4)
            }
        } header: {
            Text("How busy is it right now?")
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else {
                Text("Anonymous. Your location stays on this device.")
            }
        }
        .sensoryFeedback(.success, trigger: sent)
        .onAppear {
            sentLevel = CrowdReportLog.level(spotID: spotID).flatMap(Level.init(rawValue:))
        }
    }

    private func send(_ level: Level) async {
        isSending = true
        defer { isSending = false }
        error = nil
        do {
            try await AppConfig.apiClient.submitCrowdReport(
                spotID: spotID, deviceID: DeviceIdentity.deviceID, level: level.rawValue)
            CrowdReportLog.record(level.rawValue, spotID: spotID)
            sentLevel = level
            sent += 1
            app.track("crowd_reported", ["level": .number(Double(level.rawValue))])
        } catch let apiError as APIError where apiError.code == "rate_limited" {
            error = String(localized: "You've sent a lot of reports today. Try again tomorrow.")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "At the spot": parks and beaches are large and their point is a centroid,
/// so the radius is generous; picnic sites and tables are small.
enum CrowdProximity {
    static func radius(for kind: String) -> CLLocationDistance {
        switch kind {
        case "park", "beach": 600
        default: 150
        }
    }

    /// Only with permission already granted; one-shot location.
    @MainActor
    static func check(app: AppState, spot: CLLocationCoordinate2D?, kind: String) async -> Bool {
        guard let spot, app.location.isAuthorized,
              let here = await app.location.currentCoordinate() else { return false }
        return isNear(here, spot: spot, kind: kind)
    }

    static func isNear(_ here: CLLocationCoordinate2D, spot: CLLocationCoordinate2D, kind: String) -> Bool {
        let a = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let b = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        return a.distance(from: b) <= radius(for: kind)
    }
}

/// One report per spot per hour on this device (the server also dedupes).
enum CrowdReportLog {
    private static let key = "crowdReports"

    private static func slot(_ spotID: UUID, _ now: Date) -> String {
        "\(spotID.uuidString)@\(Int(now.startOfHour.timeIntervalSince1970))"
    }

    static func level(spotID: UUID, now: Date = .now, defaults: UserDefaults = .standard) -> Int? {
        (defaults.dictionary(forKey: key) as? [String: Int])?[slot(spotID, now)]
    }

    static func record(_ level: Int, spotID: UUID, now: Date = .now, defaults: UserDefaults = .standard) {
        var log = (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
        // Keep only the current hour's entries — older ones are useless.
        let suffix = "@\(Int(now.startOfHour.timeIntervalSince1970))"
        log = log.filter { $0.key.hasSuffix(suffix) }
        log[slot(spotID, now)] = level
        defaults.set(log, forKey: key)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
