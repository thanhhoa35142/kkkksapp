import CoreLocation
import Foundation
import Observation

/// "When in use" location, requested only from an explicit user action
/// (UI_SPEC S0/S1, UI.md permissions). Raw coordinates never leave this
/// type except as API query params; logs go through GeoMath.redactedDescription.
@MainActor @Observable
final class LocationProvider {
    private(set) var status: CLAuthorizationStatus
    private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private let delegate = Delegate()
    private var authWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    init() {
        status = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = delegate
        delegate.onAuthorization = { [weak self] status in
            MainActor.assumeIsolated { self?.authorizationChanged(status) }
        }
        delegate.onLocation = { [weak self] coordinate in
            MainActor.assumeIsolated { self?.locationArrived(coordinate) }
        }
    }

    var isAuthorized: Bool {
        #if os(iOS)
        status == .authorizedWhenInUse || status == .authorizedAlways
        #else
        status == .authorizedAlways || status == .authorized
        #endif
    }

    var isDenied: Bool { status == .denied || status == .restricted }

    /// Shows the system prompt (first time) and waits for the answer.
    func requestAuthorization() async -> CLAuthorizationStatus {
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot current location; nil when not authorized or it fails.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            locationWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    private func authorizationChanged(_ newStatus: CLAuthorizationStatus) {
        status = newStatus
        guard newStatus != .notDetermined else { return }
        let waiters = authWaiters
        authWaiters.removeAll()
        waiters.forEach { $0.resume(returning: newStatus) }
    }

    private func locationArrived(_ newCoordinate: CLLocationCoordinate2D?) {
        if let newCoordinate {
            coordinate = newCoordinate
            Log.geo.debug("location \(GeoMath.redactedDescription(of: newCoordinate))")
        }
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: newCoordinate ?? coordinate) }
    }

    /// CLLocationManager delegate callbacks arrive on the main thread because
    /// the manager is created on it; forwarded as closures.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        var onAuthorization: ((CLAuthorizationStatus) -> Void)?
        var onLocation: ((CLLocationCoordinate2D?) -> Void)?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            onAuthorization?(manager.authorizationStatus)
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            onLocation?(locations.last?.coordinate)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            Log.geo.error("location failed: \(error.localizedDescription)")
            onLocation?(nil)
        }
    }
}
