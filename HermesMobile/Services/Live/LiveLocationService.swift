import CoreLocation

struct LocationUpdate: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
    let timestamp: Date
}

@MainActor
@Observable
final class LiveLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private(set) var authorizationStatus: PermissionStatus = .notDetermined
    private(set) var lastLocation: LocationUpdate?

    var onLocationUpdate: (@MainActor (LocationUpdate) -> Void)?

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<PermissionStatus, Never>?
    private var isMonitoring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = mapStatus(manager.authorizationStatus)
    }

    func requestAuthorization() async -> PermissionStatus {
        let current = manager.authorizationStatus
        guard current == .notDetermined else {
            authorizationStatus = mapStatus(current)
            return authorizationStatus
        }

        return await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let status = manager.authorizationStatus
        if status == .authorizedAlways {
            manager.startMonitoringSignificantLocationChanges()
            manager.startMonitoringVisits()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    func requestSingleLocation() {
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authStatus = manager.authorizationStatus
        let shouldStartUpdating = authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways
        Task { @MainActor in
            let mapped = mapStatus(authStatus)
            authorizationStatus = mapped
            authContinuation?.resume(returning: mapped)
            authContinuation = nil

            if isMonitoring && shouldStartUpdating {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let alt = location.altitude
        let acc = location.horizontalAccuracy
        let ts = location.timestamp
        Task { @MainActor in
            let update = LocationUpdate(latitude: lat, longitude: lng, altitude: alt, accuracy: acc, timestamp: ts)
            lastLocation = update
            onLocationUpdate?(update)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failures are expected (e.g. indoor, no signal) — silently ignore
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lng = visit.coordinate.longitude
        guard lat != 0 || lng != 0 else { return }
        let acc = visit.horizontalAccuracy
        let ts = visit.arrivalDate
        Task { @MainActor in
            let update = LocationUpdate(latitude: lat, longitude: lng, altitude: nil, accuracy: acc, timestamp: ts)
            lastLocation = update
            onLocationUpdate?(update)
        }
    }

    private func mapStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .notDetermined
        }
    }
}
