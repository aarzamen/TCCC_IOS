import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class NineLineFormTests: XCTestCase {

    func testUnassessedPatientDoesNotInventOperationalFieldsOrReadiness() {
        let form = NineLineForm.derive(from: [PatientState(patientId: "PATIENT_1")],
            locationFix: .init(source: .gps, latitude: 34.5267, longitude: 69.1729))
        XCTAssertFalse(form.isReadyForTransmit)
        for number in [2, 3, 4, 5, 6, 7, 8, 9] {
            let entry = form.entries.first { $0.number == number }!
            XCTAssertFalse(entry.isVerifiedForTransmit, "Line \(number) needs operator input")
        }
    }

    func testUnknownAndClearedOperatorFieldsRemainPending() {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(from: [patient], locationFix: .init(source: .none, latitude: nil, longitude: nil),
            operatorValues: [3: "", 4: " UNKNOWN ", 6: "Unverified"])
        XCTAssertFalse(form.entries[2].isVerifiedForTransmit)
        XCTAssertFalse(form.entries[3].isVerifiedForTransmit)
        XCTAssertFalse(form.entries[5].isVerifiedForTransmit)
    }

    func testOnlyEnteredOperationalValuesCompleteForm() {
        let form = NineLineForm.derive(from: [],
            locationFix: .init(source: .gps, latitude: 34.5267, longitude: 69.1729),
            operatorValues: Dictionary(uniqueKeysWithValues: (2...9).map { ($0, "operator supplied line \($0)") }))
        XCTAssertEqual(form.completedCount, 9)
        XCTAssertTrue(form.isReadyForTransmit)
    }

    // Part G·NineLineForm-1: no GPS fix → Line 1 pending, form not ready.
    func testNoGPSFixLeavesLineOnePendingAndNotReady() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .none, latitude: nil, longitude: nil)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        if case .pending = lineOne.status {} else {
            XCTFail("Line 1 must be pending with no GPS fix.")
        }
        XCTAssertTrue(lineOne.value.contains("UNVERIFIED"))
        XCTAssertFalse(lineOne.isAuto)
        // Part G·NineLineForm-5: Line 1 does not count without a valid fix.
        XCTAssertEqual(form.completedCount, 1)
        XCTAssertFalse(form.isReadyForTransmit)
    }

    // Part G·NineLineForm-2: valid GPS lat/lon → full-precision MGRS, ready.
    func testGPSFixYieldsFullPrecisionMGRSAndReadyLineOne() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        // Bagram fixture — exercises the documented expected shape.
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .gps, latitude: 34.5267, longitude: 69.1729)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        XCTAssertEqual(lineOne.value, "42S WD 15867 20571")
        if case .ok = lineOne.status {} else {
            XCTFail("Line 1 must be ok for a valid GPS-derived MGRS.")
        }
        XCTAssertTrue(lineOne.isAuto, "GPS-derived Line 1 renders the GPS badge.")
        XCTAssertEqual(form.completedCount, 2)
        XCTAssertFalse(form.isReadyForTransmit)
    }

    // Part G·NineLineForm-3: GPS lat/lon present but MGRS nil (polar) →
    // Line 1 pending, not ready, no decimal-degrees fabrication.
    func testGPSFixWithUnencodableCoordinateLeavesLineOnePending() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        // 89°N is outside the MGRS/UTM band (UPS polar) → MGRS.formatted == nil.
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .gps, latitude: 89.0, longitude: 0.0)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        if case .pending = lineOne.status {} else {
            XCTFail("Line 1 must be pending when MGRS conversion fails.")
        }
        XCTAssertEqual(lineOne.value, "MGRS UNAVAILABLE")
        XCTAssertFalse(lineOne.value.contains("°"), "No decimal-degrees fallback.")
        XCTAssertEqual(form.completedCount, 1)
        XCTAssertFalse(form.isReadyForTransmit)
    }

    // Part G·NineLineForm-4: LocationSource exposes no manual/demo/mock cases.
    func testLocationSourceHasOnlyProductionCases() {
        XCTAssertEqual(AppState.LocationSource.allCases, [.none, .gps])
    }
}
