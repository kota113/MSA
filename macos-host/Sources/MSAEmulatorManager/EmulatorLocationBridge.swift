import CoreLocation
import Foundation

@MainActor
final class EmulatorLocationBridge: NSObject, @preconcurrency CLLocationManagerDelegate {
    private static let maximumAge: TimeInterval = 15
    private static let maximumAccuracy: CLLocationAccuracy = 100
    private static let minimumDistance: CLLocationDistance = 10
    private static let minimumDeliveryInterval: TimeInterval = 5

    private let manager = CLLocationManager()
    private let onLocation: (CLLocation) -> Void
    private var wantsInitialLocation = false
    private var wantsContinuousUpdates = false
    private var isUpdating = false
    private var lastDeliveredLocation: CLLocation?
    private var lastDeliveryDate: Date?
    private var pendingLocation: CLLocation?
    private var deliveryTimer: Timer?

    init(onLocation: @escaping (CLLocation) -> Void) {
        self.onLocation = onLocation
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = Self.minimumDistance
        manager.pausesLocationUpdatesAutomatically = true
    }

    func requestInitialLocation() {
        wantsInitialLocation = true
        updateManagerState()
    }

    func setContinuousUpdatesEnabled(_ enabled: Bool) {
        wantsContinuousUpdates = enabled
        if !enabled && !wantsInitialLocation {
            pendingLocation = nil
            deliveryTimer?.invalidate()
            deliveryTimer = nil
        }
        updateManagerState()
    }

    func stop() {
        wantsInitialLocation = false
        wantsContinuousUpdates = false
        pendingLocation = nil
        deliveryTimer?.invalidate()
        deliveryTimer = nil
        stopManager()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateManagerState()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: isUsable) else { return }
        if wantsInitialLocation {
            wantsInitialLocation = false
            deliver(location)
            if !wantsContinuousUpdates { stopManager() }
            return
        }
        guard wantsContinuousUpdates,
              lastDeliveredLocation.map({ location.distance(from: $0) >= Self.minimumDistance }) ?? true else {
            return
        }
        scheduleDelivery(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if !wantsContinuousUpdates {
            wantsInitialLocation = false
            stopManager()
        }
    }

    private func updateManagerState() {
        guard wantsInitialLocation || wantsContinuousUpdates else {
            stopManager()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !isUpdating else { return }
            isUpdating = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            wantsInitialLocation = false
            stopManager()
        @unknown default:
            stopManager()
        }
    }

    private func stopManager() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= Self.maximumAccuracy
            && Date().timeIntervalSince(location.timestamp) <= Self.maximumAge
            && CLLocationCoordinate2DIsValid(location.coordinate)
    }

    private func scheduleDelivery(_ location: CLLocation) {
        let remaining = Self.minimumDeliveryInterval
            - Date().timeIntervalSince(lastDeliveryDate ?? .distantPast)
        guard remaining > 0 else {
            deliver(location)
            return
        }
        pendingLocation = location
        guard deliveryTimer == nil else { return }
        deliveryTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deliveryTimer = nil
                guard self.wantsContinuousUpdates, let location = self.pendingLocation else { return }
                self.pendingLocation = nil
                self.deliver(location)
            }
        }
    }

    private func deliver(_ location: CLLocation) {
        pendingLocation = nil
        lastDeliveredLocation = location
        lastDeliveryDate = Date()
        onLocation(location)
    }
}