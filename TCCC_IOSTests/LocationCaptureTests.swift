import XCTest
import TCCCDomain
@testable import TCCC_IOS

/// Test-only location source. Mocks live in the test target ONLY — there is
/// no mock/demo runtime mode in the app (Part A/B).
struct StubLocationProvider: LocationProviding {
    let result: Result<AppState.LocationFix, LocationError>
    func requestOneShotFix() async throws -> AppState.LocationFix {
        try result.get()
    }
}

@MainActor
final class LocationCaptureTests: XCTestCase {

    /// Bagram fixture — a full-accuracy GPS fix the MGRS encoder accepts.
    private func bagramFix(
        accuracy: Double = 5,
        accuracyAuth: String = LocationAccuracyTag.full
    ) -> AppState.LocationFix {
        AppState.LocationFix(
            source: .gps,
            latitude: 34.5267,
            longitude: 69.1729,
            horizontalAccuracyMeters: accuracy,
            verticalAccuracyMeters: 8,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            authorizationStatusDescription: "authorizedWhenInUse",
            accuracyAuthorizationDescription: accuracyAuth
        )
    }

    // Part G·App-1 + App-5: a stubbed success updates locationFix and status.
    func testSuccessfulFixUpdatesLocationFixAndStatus() async {
        let state = AppState()
        state.locationProvider = StubLocationProvider(result: .success(bagramFix()))

        await state.captureGPSFix()

        XCTAssertEqual(state.locationFix.source, .gps)
        XCTAssertEqual(state.locationFix.latitude, 34.5267)
        XCTAssertEqual(state.locationFix.longitude, 69.1729)
        XCTAssertEqual(state.locationStatus, .fix(accuracyMeters: 5))
    }

    // Part G·App-5: the fix refreshes MEDEVAC LINE 1 to a ready full-MGRS row.
    func testSuccessfulFixRefreshesNineLineFormLineOne() async throws {
        let state = AppState()
        state.locationProvider = StubLocationProvider(result: .success(bagramFix()))

        await state.captureGPSFix()

        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(from: [patient], locationFix: state.locationFix)
        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        XCTAssertEqual(lineOne.value, "42S WD 15867 20571")
        XCTAssertTrue(form.isReadyForTransmit)
    }

    // Part G·App-2: denied permission → GPS DENIED state, no crash.
    func testDeniedPermissionProducesDeniedState() async {
        let state = AppState()
        state.locationProvider = StubLocationProvider(result: .failure(.denied))

        await state.captureGPSFix()

        XCTAssertEqual(state.locationStatus, .denied)
        XCTAssertEqual(state.locationFix.source, .none)
    }

    // Part G·App-3: restricted permission → GPS RESTRICTED state, no crash.
    func testRestrictedPermissionProducesRestrictedState() async {
        let state = AppState()
        state.locationProvider = StubLocationProvider(result: .failure(.restricted))

        await state.captureGPSFix()

        XCTAssertEqual(state.locationStatus, .restricted)
        XCTAssertEqual(state.locationFix.source, .none)
    }

    // Part G·App-4: reduced accuracy authorization → GPS DEGRADED state.
    func testReducedAccuracyProducesDegradedState() async {
        let state = AppState()
        let reduced = bagramFix(accuracy: 8, accuracyAuth: LocationAccuracyTag.reduced)
        state.locationProvider = StubLocationProvider(result: .success(reduced))

        await state.captureGPSFix()

        XCTAssertEqual(state.locationStatus, .degraded(accuracyMeters: 8))
        // Still usable: reduced accuracy degrades but does not block LINE 1.
        XCTAssertEqual(state.locationFix.source, .gps)
    }

    // A silent auto-refresh (launch / document generation) must not blank an
    // existing good grid on a transient miss — the operator may be about to
    // transmit it.
    func testSilentRefreshKeepsGoodFixOnTransientFailure() async {
        let state = AppState()
        state.locationProvider = StubLocationProvider(result: .success(bagramFix()))
        await state.captureGPSFix()
        XCTAssertEqual(state.locationStatus, .fix(accuracyMeters: 5))

        // Next acquisition fails transiently.
        state.locationProvider = StubLocationProvider(result: .failure(.unavailable))
        await state.captureGPSFix(silent: true)

        // Prior fix and its status are retained, not downgraded to NO FIX.
        XCTAssertEqual(state.locationStatus, .fix(accuracyMeters: 5))
        XCTAssertTrue(state.locationFix.isUsable)
        XCTAssertEqual(state.locationFix.latitude, 34.5267)
    }

    // A real GPS fix at a polar/UPS coordinate MGRS cannot encode → the
    // capture surfaces MGRS UNAVAILABLE rather than fabricating a grid.
    func testUnencodableFixProducesMGRSUnavailableState() async {
        let state = AppState()
        let polar = AppState.LocationFix(
            source: .gps, latitude: 89.0, longitude: 0.0,
            horizontalAccuracyMeters: 5
        )
        state.locationProvider = StubLocationProvider(result: .success(polar))

        await state.captureGPSFix()

        XCTAssertEqual(state.locationStatus, .mgrsUnavailable)
    }
}
