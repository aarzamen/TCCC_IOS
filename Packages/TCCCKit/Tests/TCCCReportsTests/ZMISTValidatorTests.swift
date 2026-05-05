// ZMISTValidatorTests
//
// Mirrors the contract of `validate_zmist_against_state` in
// /Users/ama/TCCC_FEB_2026/src/reports.py (lines 584–710) plus its
// helpers (_validate_zmist_section, _get_verified_signs,
// _get_verified_injuries, _get_verified_treatments,
// _get_verified_evacuation, _strip_slm_wrapper).
//
// Includes ports of the four Python tests in
// /Users/ama/TCCC_FEB_2026/tests/test_reports_validation.py.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class ZMISTValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Mirror of Python `_gsw_thigh_patient` from the Lane C regression suite.
    private func gswThighPatient(
        id: String = "PATIENT_1",
        consciousness: String = "alert",
        classification: Classification? = .urgent
    ) -> PatientState {
        return PatientState(
            patientId: id,
            mechanismOfInjury: "GSW right thigh",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "Tourniquet applied",
                hemorrhageEffective: true,
                airwayStatus: "patent",
                consciousness: consciousness
            ),
            vitals: Vitals(
                hr: 110,
                bp: BloodPressure(systolic: 90, diastolic: 60),
                spo2: 96,
                rr: 18
            ),
            classification: classification
        )
    }

    /// Walking-wounded forearm laceration. Alert, Routine.
    private func ambulatoryLacerationPatient(
        id: String = "PATIENT_2"
    ) -> PatientState {
        return PatientState(
            patientId: id,
            mechanismOfInjury: "laceration",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageLocation: "left forearm",
                hemorrhageIntervention: "Pressure dressing",
                consciousness: "alert"
            ),
            classification: .routine
        )
    }

    // MARK: - Empty patient list

    func testEmptyPatientsReturnsNoPatientsString() {
        let result = ZMISTValidator.validate("anything", against: [])
        XCTAssertEqual(result, "No patients identified in assessment.")
    }

    // MARK: - SLM wrapper stripping

    func testStripsSlmPreambleAndPostamble() {
        let patient = gswThighPatient()
        let raw = """
        Here's the ZMIST you asked for, based on the assessment:

        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1 [REDACTED]
        M (Mechanism):   GSW
        I (Injuries):    Hemorrhage: right thigh
        S (Signs):       HR 110, BP 90/60
        T (Treatment):   Tourniquet applied
        Classification:  Urgent
        Evacuation:      Litter

        Note: I've followed standard ZMIST format.
        """
        let validated = ZMISTValidator.validate(raw, against: [patient])

        XCTAssertFalse(validated.lowercased().contains("here's the zmist"),
                       "Preamble should be stripped, got:\n\(validated)")
        XCTAssertFalse(validated.lowercased().contains("i've followed"),
                       "Postamble should be stripped, got:\n\(validated)")
        XCTAssertTrue(validated.uppercased().contains("ZMIST CASUALTY REPORT"))
    }

    // MARK: - Test 1 (port): redacted Z-line binds by order, vitals replaced

    func testRedactedZlineBindsByOrderAndStripsHallucinatedVitals() {
        let patient = gswThighPatient()

        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       [REDACTED]
        M (Mechanism):   GSW
        I (Injuries):    Hemorrhage: right thigh
        S (Signs):       HR 999, BP 200/100, SpO2 15%
        T (Treatment):   Tourniquet applied
        Classification:  Urgent
        Evacuation:      Litter
        """

        let result = ZMISTValidator.validate(fakeSlm, against: [patient])

        // Hallucinated vitals must NOT survive
        XCTAssertFalse(result.contains("999"),
                       "Hallucinated HR 999 survived validation")
        XCTAssertFalse(result.contains("200/100"),
                       "Hallucinated BP 200/100 survived validation")
        XCTAssertFalse(result.contains("15%"),
                       "Hallucinated SpO2 15% survived validation")

        // State-verified vitals must be present
        XCTAssertTrue(result.contains("110"),
                      "State HR 110 missing from validated output")
        XCTAssertTrue(result.uppercased().contains("ZMIST"),
                      "Output lost ZMIST header entirely")
    }

    // MARK: - Test 2 (port): extra SLM block discarded

    func testExtraSlmBlockDiscarded() {
        let p1 = gswThighPatient(id: "PATIENT_1")
        let p2 = ambulatoryLacerationPatient(id: "PATIENT_2")

        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       [REDACTED]
        M (Mechanism):   GSW
        I (Injuries):    Hemorrhage: right thigh
        S (Signs):       HR 110, BP 90/60
        T (Treatment):   Tourniquet applied
        Classification:  Urgent
        Evacuation:      Litter

        ---

        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       [REDACTED]
        M (Mechanism):   laceration
        I (Injuries):    laceration forearm
        S (Signs):       HR 72, BP 120/78
        T (Treatment):   Pressure dressing
        Classification:  Priority
        Evacuation:      Ambulatory

        ---

        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       [REDACTED]
        M (Mechanism):   HALLUCINATED_PATIENT_DO_NOT_EMIT
        I (Injuries):    Made-up injury
        S (Signs):       HR 42, BP 50/30
        T (Treatment):   FAKE_TREATMENT_XYZ
        Classification:  Urgent Surgical
        Evacuation:      Litter
        """

        let result = ZMISTValidator.validate(fakeSlm, against: [p1, p2])

        // Hallucinated content from third block must NOT appear in output.
        XCTAssertFalse(result.contains("HALLUCINATED_PATIENT_DO_NOT_EMIT"))
        XCTAssertFalse(result.contains("FAKE_TREATMENT_XYZ"))
        XCTAssertFalse(result.contains("Made-up injury"))

        // Legitimate ZMIST content survives.
        XCTAssertTrue(result.uppercased().contains("ZMIST"))
    }

    // MARK: - Block-by-block fields are replaced with state-verified values

    func testValidatedSignsLineUsesStateVitals() {
        let patient = gswThighPatient()
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        S (Signs):       HR 999, BP 200/100
        I (Injuries):    Some made up injury list
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        XCTAssertTrue(result.contains("S (Signs):"))
        XCTAssertTrue(result.contains("HR 110"))
        XCTAssertTrue(result.contains("BP 90/60"))
        XCTAssertFalse(result.contains("HR 999"))
    }

    func testValidatedInjuriesLineUsesStateMarch() {
        let patient = gswThighPatient()
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        I (Injuries):    sucking chest wound, decapitation, total amputation
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        // State-verified injuries are hemorrhage location only.
        XCTAssertTrue(result.contains("Hemorrhage: right thigh"))
        XCTAssertFalse(result.contains("decapitation"))
        XCTAssertFalse(result.contains("amputation"))
    }

    func testValidatedTreatmentLineUsesStateInterventions() {
        let patient = gswThighPatient()
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        T (Treatment):   Cricothyroidotomy, thoracotomy, blood transfusion x4
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        XCTAssertTrue(result.contains("Tourniquet applied"))
        XCTAssertFalse(result.contains("Cricothyroidotomy"))
        XCTAssertFalse(result.contains("thoracotomy"))
    }

    // MARK: - Evacuation override

    func testEvacuationOverriddenToLitterForGSWThigh() {
        let patient = gswThighPatient()
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        Evacuation:      Ambulatory
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        XCTAssertTrue(result.contains("Evacuation:      Litter"),
                      "Expected Evacuation: Litter override; got:\n\(result)")
        XCTAssertFalse(result.contains("Evacuation:      Ambulatory"))
    }

    // MARK: - Classification line uses state classification

    func testClassificationLineMirrorsStateClassification() {
        let patient = gswThighPatient(classification: .urgentSurgical)
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        Classification:  Routine
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        XCTAssertTrue(result.contains("Classification:  Urgent Surgical"))
        XCTAssertFalse(result.contains("Classification:  Routine"))
    }

    func testClassificationLineFallsBackToPendingWhenNil() {
        let patient = gswThighPatient(classification: nil)
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        Classification:  Convenience
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [patient])
        XCTAssertTrue(result.contains("Classification:  PENDING"))
    }

    // MARK: - Missing block path: synthesise from state

    func testMissingPatientBlockGeneratesFromState() {
        // Two patients in state, only one block in SLM output.
        let p1 = gswThighPatient(id: "PATIENT_1")
        let p2 = ambulatoryLacerationPatient(id: "PATIENT_2")
        let fakeSlm = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        S (Signs):       HR 110, BP 90/60
        T (Treatment):   Tourniquet applied
        """
        let result = ZMISTValidator.validate(fakeSlm, against: [p1, p2])
        // Both patient IDs should now appear (PATIENT_2 via state-fallback).
        XCTAssertTrue(result.contains("PATIENT_1"))
        XCTAssertTrue(result.contains("PATIENT_2"))
    }

    // MARK: - Last-resort fallback when nothing survives

    func testReturnsStateGeneratedWhenNoZMISTContent() {
        let patient = gswThighPatient()
        let result = ZMISTValidator.validate(
            "Sorry I cannot help with that request",
            against: [patient]
        )
        XCTAssertTrue(result.uppercased().contains("ZMIST"),
                      "Expected fallback ZMIST report, got:\n\(result)")
        XCTAssertTrue(result.contains("PATIENT_1"))
    }
}
