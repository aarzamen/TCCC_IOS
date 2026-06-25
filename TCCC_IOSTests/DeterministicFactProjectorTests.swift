// TCCC_IOSTests/DeterministicFactProjectorTests.swift
import XCTest
import TCCCDomain
@testable import TCCC_IOS

final class DeterministicFactProjectorTests: XCTestCase {
    func testProjectsPopulatedFieldsWithRubricFieldNames() {
        var state = PatientState(patientId: "PATIENT_1")
        state.vitals.hr = 88
        state.march.hemorrhageLocation = "left thigh"
        let facts = DeterministicFactProjector.project(state)

        XCTAssertTrue(facts.contains { $0.domain == "vitals" && $0.field == "heartRate" && $0.value == "88" })
        XCTAssertTrue(facts.contains { $0.domain == "march" && $0.field == "hemorrhageLocation" && $0.value == "left thigh" })
        // empty fields are not projected
        XCTAssertFalse(facts.contains { $0.field == "spo2" })
        // best-effort evidence this cycle (debt gated on the event log)
        XCTAssertTrue(facts.allSatisfy { $0.evidenceIds.isEmpty && $0.confidence == .high })
    }

    func testEmptyStateProjectsNothing() {
        XCTAssertTrue(DeterministicFactProjector.project(PatientState(patientId: "PATIENT_1")).isEmpty)
    }

    func testAntibioticsFieldNameMatchesAllowedFieldsSingular() {
        // Regression: projector must emit "antibiotic" (singular) so GraniteSchemaValidator
        // does not reject it as .unknownField("antibiotics").
        var state = PatientState(patientId: "PATIENT_1")
        state.paws.antibiotics = "ceftriaxone"
        let facts = DeterministicFactProjector.project(state)
        XCTAssertTrue(
            facts.contains { $0.domain == "paws" && $0.field == "antibiotic" && $0.value == "ceftriaxone" },
            "Expected paws/antibiotic fact but got: \(facts.map { "\($0.domain)/\($0.field)=\($0.value)" })"
        )
    }
}
