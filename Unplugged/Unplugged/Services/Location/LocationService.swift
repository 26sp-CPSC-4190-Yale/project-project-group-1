import CoreLocation
import Foundation
import UnpluggedShared

struct LockInLocationSnapshot: Sendable {
    let coordinate: CLLocationCoordinate2D
}

enum LocationSnapshotError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission is required to add this to your memento."
        case .locationUnavailable:
            return "Couldn't get your current location. Try again in a moment."
        }
    }
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func lockInSnapshot(requestPermissionIfNeeded: Bool) async -> LockInLocationSnapshot? {
        try? await mementoSnapshot(requestPermissionIfNeeded: requestPermissionIfNeeded)
    }

    func mementoSnapshot(requestPermissionIfNeeded: Bool) async throws -> LockInLocationSnapshot {
        var status = manager.authorizationStatus
        if status == .notDetermined, requestPermissionIfNeeded {
            status = await requestAuthorization()
        }

        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            throw LocationSnapshotError.permissionDenied
        }

        guard let location = await requestLocation() ?? manager.location else {
            throw LocationSnapshotError.locationUnavailable
        }
        return LockInLocationSnapshot(coordinate: location.coordinate)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationContinuation?.resume(returning: manager.authorizationStatus)
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            continuation?.resume(returning: locations.last)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.authorizationContinuation?.resume(returning: manager.authorizationStatus)
                self.authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        } onCancel: {
            Task { @MainActor in
                authorizationContinuation?.resume(returning: manager.authorizationStatus)
                authorizationContinuation = nil
            }
        }
    }

    private func requestLocation() async -> CLLocation? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation?.resume(returning: nil)
                self.continuation = continuation
                manager.requestLocation()
            }
        } onCancel: {
            Task { @MainActor in
                continuation?.resume(returning: nil)
                continuation = nil
            }
        }
    }
}
