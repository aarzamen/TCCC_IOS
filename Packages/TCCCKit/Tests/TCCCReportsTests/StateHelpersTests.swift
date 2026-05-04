// StateHelpersTests
//
// Direct exercises of the internal helpers ported from
// /Users/ama/TCCC_FEB_2026/src/reports.py. These reach into @testable internals
// because the helpers don't have a public surface — only the generators do.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class StateHelpersTests: XCTestCase {

    // ---------------------------------------------------------- counts

    func testCountsEmptyList() {
        let counts = StateHelpers.calculatePatientCounts([])
        XCTAssertEqual(counts.urgent, 0)
        XCTAssertEqual(counts.urgentSurgical, 0)
        XCTAssertEqual(counts.priority, 0)
        XCTAssertEqual(counts.routine, 0)
        XCTAssertEqual(counts.convenience, 0)
        XCTAssertEqual(counts.total, 0)
    }

    func testCountsUrgentSurgicalDoesNotMatchUrgentBucket() {
        let p = PatientState(patientId: "PATIENT_1", classification: .urgentSurgical)
        let counts = StateHelpers.calculatePatientCounts([p])
        XCTAssertEqual(counts.urgentSurgical, 1)
        XCTAssertEqual(counts.urgent, 0)
    }

    func testCountsRoutine() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert"),
            classification: .routine
        )
        let counts = StateHelpers.calculatePatientCounts([p])
        XCTAssertEqual(counts.routine, 1)
    }

    func testCountsUnclassifiedDefaultsToUrgent() {
        // No classification -> infer -> default urgent (Python conservative).
        let p = PatientState(patientId: "PATIENT_1")
        let counts = StateHelpers.calculatePatientCounts([p])
        XCTAssertEqual(counts.urgent, 1)
    }

    // ---------------------------------------------------------- inference

    func testInferUrgentSurgicalFromChestSeal() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(respirationIntervention: "Chest seal applied")
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "urgent surgical")
    }

    func testInferUrgentSurgicalFromUnresponsive() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Unresponsive")
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "urgent surgical")
    }

    func testInferUrgentFromTourniquet() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(hemorrhageIntervention: "Tourniquet applied")
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "urgent")
    }

    func testInferUrgentFromHRoverHundred() {
        let p = PatientState(
            patientId: "PATIENT_1",
            vitals: Vitals(hr: 138)
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "urgent")
    }

    func testInferUrgentFromHypotensiveBP() {
        let p = PatientState(
            patientId: "PATIENT_1",
            vitals: Vitals(bp: BloodPressure(systolic: 80, diastolic: 40))
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "urgent")
    }

    func testInferPriorityFromIdentifiedHemorrhageWithoutIntervention() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(hemorrhageIdentified: true)
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "priority")
    }

    func testInferRoutineForAlertPatientWithNoInterventions() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert")
        )
        XCTAssertEqual(StateHelpers.inferClassification(p), "routine")
    }

    // ---------------------------------------------------------- evac

    func testNeedsLitterUnconscious() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Unresponsive")
        )
        XCTAssertTrue(StateHelpers.needsLitter(p))
    }

    func testNeedsLitterTourniquetOnThigh() {
        // Mirrors Python test_generate_zmist_from_state_litter_for_gsw_thigh.
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(
                hemorrhageIdentified: true,
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "Tourniquet applied",
                hemorrhageEffective: true,
                consciousness: "Alert"
            ),
            classification: .urgent
        )
        XCTAssertTrue(StateHelpers.needsLitter(p))
    }

    func testAlertWithMinorForearmLacerationIsNotLitter() {
        // Mirrors Python test_generate_zmist_ambulatory_for_minor_laceration.
        let march = MARCHState(
            hemorrhageLocation: "left forearm",
            hemorrhageIntervention: "Pressure dressing",
            consciousness: "Alert"
        )
        let p = PatientState(
            patientId: "PATIENT_1",
            march: march,
            classification: .routine
        )
        XCTAssertFalse(StateHelpers.needsLitter(p))
    }

    func testLitterAmbulatoryMixedTwoPatients() {
        let urgent = PatientState(
            patientId: "P1",
            march: MARCHState(
                hemorrhageLocation: "right thigh",
                hemorrhageIntervention: "Tourniquet",
                consciousness: "Alert"
            ),
            classification: .urgent
        )
        let routine = PatientState(
            patientId: "P2",
            march: MARCHState(
                hemorrhageLocation: "left forearm",
                hemorrhageIntervention: "Pressure dressing",
                consciousness: "Alert"
            ),
            classification: .routine
        )
        let split = StateHelpers.calculateLitterAmbulatory([urgent, routine])
        XCTAssertEqual(split.litter, 1)
        XCTAssertEqual(split.ambulatory, 1)
    }

    // ---------------------------------------------------------- equipment

    func testHoistKeywordSelectsBHoist() {
        let eq = StateHelpers.determineSpecialEquipment(
            transcript: "we'll need a hoist for extraction off the cliff",
            patients: []
        )
        XCTAssertEqual(eq, "B-Hoist")
    }

    func testExtractionKeywordSelectsCExtraction() {
        let eq = StateHelpers.determineSpecialEquipment(
            transcript: "vehicle extraction required",
            patients: []
        )
        XCTAssertEqual(eq, "C-Extraction")
    }

    func testVentilatorKeywordSelectsDVentilator() {
        let eq = StateHelpers.determineSpecialEquipment(
            transcript: "patient needs a ventilator",
            patients: []
        )
        XCTAssertEqual(eq, "D-Ventilator")
    }

    func testVentStandaloneSelectsDVentilator() {
        let eq = StateHelpers.determineSpecialEquipment(
            transcript: "put him on the vent now",
            patients: []
        )
        XCTAssertEqual(eq, "D-Ventilator")
    }

    func testPreventDoesNotMatchVent() {
        // Word boundary check: "prevent" must not trigger vent matching.
        let eq = StateHelpers.determineSpecialEquipment(
            transcript: "we want to prevent shock",
            patients: []
        )
        XCTAssertEqual(eq, "A-None")
    }

    func testCricothyroidotomyImpliesVentilator() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(airwayIntervention: "Surgical cricothyroidotomy performed")
        )
        let eq = StateHelpers.determineSpecialEquipment(transcript: "", patients: [p])
        XCTAssertEqual(eq, "D-Ventilator")
    }

    func testNoIndicatorReturnsANone() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert"),
            classification: .routine
        )
        let eq = StateHelpers.determineSpecialEquipment(transcript: "", patients: [p])
        XCTAssertEqual(eq, "A-None")
    }
}
