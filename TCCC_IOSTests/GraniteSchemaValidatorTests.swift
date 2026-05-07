import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteSchemaValidatorTests: XCTestCase {
    func testRejectsEmptyNoOpPatch() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.emptyPatch))
    }

    func testRejectsFactWithoutEvidence() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "march",
                    field: "hemorrhageIntervention",
                    value: "tourniquet",
                    evidenceIds: [],
                    confidence: .high
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.missingEvidenceIds(factId: "fact-1")))
    }

    func testRejectsUnknownEvidenceId() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "march",
                    field: "hemorrhageIntervention",
                    value: "tourniquet",
                    evidenceIds: ["seg-missing"],
                    confidence: .high
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.unknownEvidenceId(factId: "fact-1", evidenceId: "seg-missing")))
    }

    func testRejectsUnknownPatient() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_2",
            candidateFacts: [],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.unknownPatient(patientId: "PATIENT_2")))
    }

    func testRejectsUnknownField() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "march",
                    field: "madeUpField",
                    value: "normal",
                    evidenceIds: ["seg-1"],
                    confidence: .high
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.unknownField(field: "madeUpField")))
    }

    func testRejectsImpossibleNumericValue() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: "400",
                    evidenceIds: ["seg-1"],
                    confidence: .high
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertFalse(result.isAccepted)
        XCTAssertTrue(result.errors.contains(.impossibleValue(field: "heartRate", value: "400")))
    }

    func testUnknownNullFactIsAllowedWithoutEvidence() {
        let patch = GraniteCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: nil,
                    evidenceIds: [],
                    confidence: .unknown
                )
            ],
            conflicts: [],
            missingRequiredFields: ["heartRate"],
            rejectedInputs: [],
            modelSelfCheck: "json valid"
        )

        let result = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: ["seg-1"],
            knownPatientIds: ["PATIENT_1"]
        )

        XCTAssertTrue(result.isAccepted)
        XCTAssertEqual(result.acceptedFacts.count, 1)
    }
}
