import XCTest
@testable import TCCCDomain

final class PatientStateTests: XCTestCase {

    func testDefaultsMirrorPythonFrozenDataclass() {
        let p = PatientState(patientId: "PATIENT_1")
        XCTAssertEqual(p.patientId, "PATIENT_1")
        XCTAssertNil(p.mechanismOfInjury)
        XCTAssertEqual(p.march, MARCHState())
        XCTAssertEqual(p.vitals, Vitals())
        XCTAssertTrue(p.interventions.isEmpty)
        XCTAssertTrue(p.injuries.isEmpty)
        XCTAssertEqual(p.marchPhase, .massive) // mirrors `march_phase: str = "M"`
        XCTAssertNil(p.classification)
        XCTAssertEqual(p.paws, PAWSAssessment())
        XCTAssertNil(p.timestampFirstMention)
        XCTAssertNil(p.timestampLastUpdate)
    }

    func testIdMirrorsPatientId() {
        let p = PatientState(patientId: "PATIENT_42")
        XCTAssertEqual(p.id, "PATIENT_42")
    }

    func testCodableRoundTripWithNestedData() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let intervention = Intervention(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: timestamp,
            kind: .tourniquet,
            description: "Tourniquet applied to right thigh"
        )
        let original = PatientState(
            patientId: "PATIENT_1",
            mechanismOfInjury: "GSW",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageAssessed: true,
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "Tourniquet applied",
                hemorrhageEffective: true,
                airwayStatus: "patent",
                respirationStatus: "normal",
                pulseStatus: "weak radial",
                skinSigns: "pale",
                consciousness: "Alert"
            ),
            vitals: Vitals(
                hr: 128,
                bp: BloodPressure(systolic: 92, diastolic: 60),
                spo2: 96,
                rr: 22,
                gcs: 15
            ),
            interventions: [intervention],
            injuries: ["right femur fracture", "GSW right thigh"],
            marchPhase: .circulation,
            classification: .urgent,
            paws: PAWSAssessment(
                pain: "Combat pill pack administered",
                antibiotics: "Moxifloxacin administered",
                wounds: "Wound care performed",
                splinting: "SAM splint"
            ),
            timestampFirstMention: 1_700_000_000.0,
            timestampLastUpdate: 1_700_000_500.0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PatientState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEqualityIsValueBased() {
        let a = PatientState(patientId: "PATIENT_1", classification: .priority)
        let b = PatientState(patientId: "PATIENT_1", classification: .priority)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testInequalityWhenClassificationDiffers() {
        let a = PatientState(patientId: "PATIENT_1", classification: .priority)
        let b = PatientState(patientId: "PATIENT_1", classification: .urgent)
        XCTAssertNotEqual(a, b)
    }
}
