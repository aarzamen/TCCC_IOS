import CoreLocation
import Foundation

/// Stable string tags for `CLAccuracyAuthorization`, shared by the provider
/// (which writes them into `LocationFix`) and `AppState` (which reads them
/// back to decide GPS FIX vs GPS DEGRADED). One source of truth, no magic
/// strings duplicated across files.
enum LocationAccuracyTag {
    static let full = "full"
    static let reduced = "reduced"
    static let unknown = "unknown"
}

/// One-shot device-location source for MEDEVAC LINE 1.
///
/// Production rule: the app's only runtime location source is the real
/// iPhone GPS. Test doubles conform to this protocol but live in the test
/// target only — there is no mock/demo runtime mode.
protocol LocationProviding: Sendable {
    /// Request a single GPS fix. Drives the system permission prompt the
    /// first time, then returns one fix (or throws). Never starts
    /// continuous tracking.
    func requestOneShotFix() async throws -> AppState.LocationFix
}

enum LocationError: Error, Sendable, Equatable {
    case denied            // operator denied Location for this app
    case restricted        // Location disallowed by device policy
    case unavailable       // no fix returned / CoreLocation error
    case alreadyInProgress // a request is already outstanding
}

/// CoreLocation-backed one-shot provider. Operator-gated: nothing here runs
/// until `requestOneShotFix()` is called from a USE GPS FIX tap. Uses
/// `requestLocation()` (inherently single-shot) — no `startUpdatingLocation`,
/// no background mode, no continuous tracking to tear down, no reverse
/// geocoding, no map SDK, no upload.
@MainActor
final class CoreLocationProvider: NSObject, LocationProviding {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<AppState.LocationFix, Error>?
    private var awaitingAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestOneShotFix() async throws -> AppState.LocationFix {
        // One outstanding request at a time — never spam permission prompts
        // or stack continuations.
        guard continuation == nil else { throw LocationError.alreadyInProgress }

        switch manager.authorizationStatus {
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.restricted
        case .authorizedWhenInUse, .authorizedAlways:
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
                manager.requestLocation()
            }
        case .notDetermined:
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
                awaitingAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw LocationError.unavailable
        }
    }

    /// Resume the outstanding request exactly once, then clear state.
    private func finish(_ result: Result<AppState.LocationFix, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        awaitingAuthorization = false
        cont.resume(with: result)
    }

    fileprivate func handleAuthorizationChange() {
        // The delegate fires once on assignment with the current status;
        // only act when we are actually awaiting the operator's choice.
        guard awaitingAuthorization else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            awaitingAuthorization = false
            manager.requestLocation()
        case .denied:
            finish(.failure(LocationError.denied))
        case .restricted:
            finish(.failure(LocationError.restricted))
        case .notDetermined:
            break   // still waiting on the prompt — do not retry/spam
        @unknown default:
            finish(.failure(LocationError.unavailable))
        }
    }

    fileprivate func handleLocations(_ locations: [CLLocation]) {
        guard let loc = locations.last else {
            finish(.failure(LocationError.unavailable)); return
        }
        let fix = AppState.LocationFix(
            source: .gps,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            horizontalAccuracyMeters: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil,
            verticalAccuracyMeters: loc.verticalAccuracy >= 0 ? loc.verticalAccuracy : nil,
            capturedAt: loc.timestamp,
            authorizationStatusDescription: Self.describe(manager.authorizationStatus),
            accuracyAuthorizationDescription: Self.describe(manager.accuracyAuthorization)
        )
        finish(.success(fix))
    }

    fileprivate func handleFailure(_ error: Error) {
        // A CLError here means no usable fix this attempt; surface it as
        // unavailable rather than crashing on the field-device path.
        finish(.failure(LocationError.unavailable))
    }

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:       "notDetermined"
        case .restricted:          "restricted"
        case .denied:              "denied"
        case .authorizedAlways:    "authorizedAlways"
        case .authorizedWhenInUse: "authorizedWhenInUse"
        @unknown default:          "unknown"
        }
    }

    static func describe(_ accuracy: CLAccuracyAuthorization) -> String {
        switch accuracy {
        case .fullAccuracy:    LocationAccuracyTag.full
        case .reducedAccuracy: LocationAccuracyTag.reduced
        @unknown default:      LocationAccuracyTag.unknown
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    // CLLocationManager is created on the main actor, so it delivers its
    // delegate callbacks on the main run loop — `assumeIsolated` is valid.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { self.handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { self.handleLocations(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.handleFailure(error) }
    }
}
