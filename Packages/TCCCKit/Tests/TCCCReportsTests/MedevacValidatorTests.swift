// MedevacValidatorTests
//
// Mirrors the contract of `validate_medevac_against_state` in
// /Users/ama/TCCC_FEB_2026/src/reports.py (lines 20–92) and its helpers
// (_calculate_patient_counts, _infer_classification,
// _calculate_litter_ambulatory, _determine_special_equipment,
// _strip_slm_wrapper).
//
// Each test feeds bogus SLM output through MedevacValidator.validate
// and asserts that confabulated values were replaced with state-verified
// values, while leaving unrelated lines untouched.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class MedevacValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Single GSW right-thigh patient with a tourniquet applied — our canonical
    /// "1 litter, 1 urgent" case.
    private func gswThighPatient(
        id: String = "PATIENT_1",
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
                consciousness: "alert"
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

    /// A walking-wounded forearm laceration — alert, no leg/airway/resp issue.
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
        let result = MedevacValidator.validate(
            "anything",
            against: [],
            transcript: ""
        )
        XCTAssertEqual(result, "No patients identified in assessment.")
    }

    // MARK: - Line 5 (Litter / Ambulatory) correction

    func testCorrectsLine5LitterAmbulatoryFromState() {
        let patients = [gswThighPatient()]  // 1 litter, 0 ambulatory
        let bogus = """
        9-LINE MEDEVAC REQUEST
        =====================
        Line 1 (Location):       MGRS 12ABC34567890
        Line 2 (Frequency):      38.65 FM
        Line 3 (Precedence):     A-7
        Line 4 (Special Equip):  D-Ventilator
        Line 5 (# Patients):     A-Litter: 7, B-Ambulatory: 2
        """
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: ""
        )
        XCTAssertTrue(validated.contains("A-Litter: 1"),
                      "Expected A-Litter: 1, got:\n\(validated)")
        XCTAssertTrue(validated.contains("B-Ambulatory: 0"),
                      "Expected B-Ambulatory: 0, got:\n\(validated)")
        XCTAssertFalse(validated.contains("A-Litter: 7"),
                       "Hallucinated A-Litter: 7 survived validation")
    }

    // MARK: - Line 4 (Special Equipment)

    func testCorrectsLine4SpecialEquipment_DefaultsToNoneWhenTranscriptSilent() {
        let patients = [gswThighPatient()]
        let bogus = "Line 4 (Special Equip):  D-Ventilator"
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: ""
        )
        XCTAssertTrue(validated.contains("Line 4 (Special Equip):  A-None"))
        XCTAssertFalse(validated.contains("D-Ventilator"))
    }

    func testLine4InfersHoistFromTranscript() {
        let patients = [gswThighPatient()]
        let bogus = "Line 4 (Special Equip):  A-None"
        let transcript = "Need helo hoist for casualty extraction off the ridge."
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: transcript
        )
        // "hoist" wins over "extraction" (Python checks them in that order).
        XCTAssertTrue(validated.contains("B-Hoist"))
    }

    func testLine4InfersExtractionFromTranscript() {
        let patients = [gswThighPatient()]
        let bogus = "Line 4 (Special Equip):  A-None"
        let transcript = "Vehicle extraction underway, casualty pinned."
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: transcript
        )
        XCTAssertTrue(validated.contains("C-Extraction"))
    }

    // MARK: - Line 3 (Precedence) correction

    func testCorrectsLine3PrecedenceCounts() {
        // 1 urgent (gswThigh) + 1 routine (ambulatory) — Python format
        // is "A-{u}, B-{us}, C-{p}, D-{r}, E-{c}".
        let patients = [gswThighPatient(), ambulatoryLacerationPatient()]
        let bogus = "Line 3 (Precedence):     A-9, B-9, C-9, D-9, E-9"
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: ""
        )
        XCTAssertTrue(validated.contains("A-1, B-0, C-0, D-1, E-0"),
                      "Expected A-1, B-0, C-0, D-1, E-0; got:\n\(validated)")
    }

    // MARK: - Expanded count lines (A - Urgent: X)

    func testCorrectsExpandedUrgentCount() {
        let patients = [gswThighPatient(), gswThighPatient(id: "PATIENT_2")]
        let bogus = "                         A - Urgent: 99"
        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: ""
        )
        XCTAssertTrue(validated.contains("A - Urgent: 2"))
        XCTAssertFalse(validated.contains("A - Urgent: 99"))
    }

    func testCorrectsExpandedUrgentSurgicalCount() {
        // Patient with chest seal -> urgent surgical
        let patient = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(
                respirationIntervention: "Chest seal applied"
            )
        )
        let bogus = "                         B - Urgent Surgical: 0"
        let validated = MedevacValidator.validate(
            bogus,
            against: [patient],
            transcript: ""
        )
        XCTAssertTrue(validated.contains("B - Urgent Surgical: 1"),
                      "got:\n\(validated)")
    }

    // MARK: - SLM preamble / postamble stripping

    func testStripsSlmPreamble() {
        let patients = [gswThighPatient()]
        let raw = """
        Sure, here is the 9-Line MEDEVAC you requested:

        9-LINE MEDEVAC REQUEST
        =====================
        Line 5 (# Patients):     A-Litter: 5, B-Ambulatory: 5
        """
        let validated = MedevacValidator.validate(
            raw,
            against: patients,
            transcript: ""
        )
        XCTAssertFalse(validated.lowercased().contains("here is the 9-line"),
                       "Preamble should be stripped, got:\n\(validated)")
        XCTAssertTrue(validated.contains("A-Litter: 1"))
    }

    // MARK: - Non-targeted lines pass through untouched

    func testNonTargetedLinesPassThrough() {
        let patients = [gswThighPatient()]
        let raw = """
        9-LINE MEDEVAC REQUEST
        =====================
        Line 1 (Location):       MGRS 12ABC34567890
        Line 2 (Frequency):      38.65 FM, callsign DUSTOFF 6
        Line 6 (Security):       N-No enemy
        Line 7 (Marking):        C-Smoke
        Line 8 (Nationality):    A-US Military
        Line 9 (CBRN):           N-No CBRN
        """
        let validated = MedevacValidator.validate(
            raw,
            against: patients,
            transcript: ""
        )
        XCTAssertTrue(validated.contains("Line 1 (Location):       MGRS 12ABC34567890"))
        XCTAssertTrue(validated.contains("Line 6 (Security):       N-No enemy"))
        XCTAssertTrue(validated.contains("Line 9 (CBRN):           N-No CBRN"))
    }

    // MARK: - Classification override — PENDING infers from clinical findings

    func testPendingClassificationInferredAsUrgent() {
        // No classification set (== PENDING) but tourniquet applied -> urgent.
        let patient = gswThighPatient(classification: nil)
        let bogus = "Line 3 (Precedence):     A-0, B-0, C-9, D-0, E-0"
        let validated = MedevacValidator.validate(
            bogus,
            against: [patient],
            transcript: ""
        )
        XCTAssertTrue(validated.contains("A-1, B-0, C-0, D-0, E-0"))
    }
}
