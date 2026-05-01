import CoreLocation
import Foundation
import UnpluggedShared
#if canImport(WeatherKit)
import WeatherKit
#endif

struct LockInLocationSnapshot: Sendable {
    let coordinate: CLLocationCoordinate2D
    let weather: SessionWeatherSnapshot?
}

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func lockInSnapshot(requestPermissionIfNeeded: Bool) async -> LockInLocationSnapshot? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            guard requestPermissionIfNeeded else { return nil }
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(for: .milliseconds(300))
        }

        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return nil
        }

        guard let location = await requestLocation() ?? manager.location else { return nil }
        let weather = await weatherSnapshot(for: location)
        return LockInLocationSnapshot(coordinate: location.coordinate, weather: weather)
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

    private func weatherSnapshot(for location: CLLocation) async -> SessionWeatherSnapshot? {
        #if canImport(WeatherKit)
        if #available(iOS 16.0, *) {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                return SessionWeatherSnapshot(
                    summary: weather.currentWeather.condition.description,
                    temperatureFahrenheit: weather.currentWeather.temperature.converted(to: .fahrenheit).value,
                    conditionSymbol: weather.currentWeather.symbolName,
                    capturedAt: Date()
                )
            } catch {
                AppLogger.room.warning(
                    "WeatherKit snapshot failed",
                    context: ["error": String(describing: error)]
                )
            }
        }
        #endif
        return nil
    }
}
