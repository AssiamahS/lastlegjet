import Foundation
import CoreLocation

/// One-shot "where is this phone" for operator status updates and the nearest-airport shortcut.
/// Returns nil when permission is denied or no fix arrives before the timeout.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authWaiters: [CheckedContinuation<Void, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    func currentLocation(timeout: TimeInterval = 6) async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                authWaiters.append(c)
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else { return nil }
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -120 {
            return recent
        }
        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            waiters.append(c)
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.finish(self.manager.location)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let pending = self.authWaiters
            self.authWaiters.removeAll()
            pending.forEach { $0.resume() }
        }
    }
}
