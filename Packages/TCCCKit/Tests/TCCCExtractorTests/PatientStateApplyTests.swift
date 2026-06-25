// PatientStateApplyTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PatientStateApplyTests: XCTestCase {
    func testApplyHeartRateMutatesVitalsThroughEngine() async {
        let engine = PatientStateEngine.standard()
        await engine.apply([.heartRate(88)], to: "PATIENT_1")
        let p = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(p?.vitals.hr, 88)
    }

    func testApplyBloodPressureAndMarchFields() async {
        let engine = PatientStateEngine.standard()
        await engine.apply([
            .bloodPressure(systolic: 120, diastolic: 80, palpated: false),
            .hemorrhageLocation("left thigh"),
        ], to: "PATIENT_1")
        let p = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(p?.vitals.bp?.systolic, 120)
        XCTAssertEqual(p?.march.hemorrhageLocation, "left thigh")
    }
}
