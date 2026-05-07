import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class NineLineFormTests: XCTestCase {
    func testPendingLocationDoesNotCompleteOrTransmitNineLine() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .none, latitude: nil, longitude: nil)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        if case .pending = lineOne.status {
            // expected
        } else {
            XCTFail("Line 1 should be pending when no location source is usable.")
        }
        XCTAssertTrue(lineOne.value.contains("UNVERIFIED"))
        XCTAssertFalse(lineOne.isAuto)
        XCTAssertEqual(form.completedCount, 8)
        XCTAssertFalse(form.isReadyForTransmit)
    }

    func testDemoLocationDoesNotCompleteOrTransmitNineLine() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .demo, latitude: 34.0, longitude: 69.0)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        if case .demo = lineOne.status {
            // expected
        } else {
            XCTFail("Line 1 should keep demo provenance when training coordinates are used.")
        }
        XCTAssertFalse(lineOne.isAuto)
        XCTAssertEqual(form.completedCount, 8)
        XCTAssertFalse(form.isReadyForTransmit)
    }

    func testManualLocationCompletesAndTransmitsNineLine() throws {
        let patient = PatientState(patientId: "PATIENT_1", classification: .urgent)
        let form = NineLineForm.derive(
            from: [patient],
            locationFix: .init(source: .manual, latitude: 34.0, longitude: 69.0)
        )

        let lineOne = try XCTUnwrap(form.entries.first { $0.number == 1 })
        XCTAssertFalse(lineOne.isAuto)
        XCTAssertEqual(form.completedCount, 9)
        XCTAssertTrue(form.isReadyForTransmit)
    }
}
