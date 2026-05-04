// MedevacGeneratorTests
//
// Per-line assertions for the 9-Line MEDEVAC fallback. Mirrors the Python
// fixtures in /Users/ama/TCCC_FEB_2026/tests/test_reports_validation.py and
// the helper-function semantics from
// /Users/ama/TCCC_FEB_2026/src/reports.py.

import XCTest
@testable import TCCCReports
import TCCCDomain

final class MedevacGeneratorTests: XCTestCase {

    // ---------------------------------------------------------------- helpers

    /// GSW right thigh + tourniquet, alert, Urgent — same as Python
    /// `_gsw_thigh_patient`.
    private func gswThighPatient(
        id: String = "PATIENT_1",
        consciousness: String = "Alert",
        classification: Classification? = .urgent
    ) -> PatientState {
        let march = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageLocation: "right thigh",
            hemorrhageIntervention: "Tourniquet applied",
            hemorrhageEffective: true,
            airwayStatus: "patent",
            consciousness: consciousness
        )
        return PatientState(
            patientId: id,
            mechanismOfInjury: "GSW right thigh",
            march: march,
            vitals: Vitals(
                hr: 110,
                bp: BloodPressure(systolic: 90, diastolic: 60),
                spo2: 96,
                rr: 18
            ),
            classification: classification
        )
    }

    /// Minor laceration patient — alert, Routine — should be ambulatory.
    private func minorLacerationPatient(id: String = "PATIENT_2") -> PatientState {
        let march = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageLocation: "left forearm",
            hemorrhageIntervention: "Pressure dressing",
            consciousness: "Alert"
        )
        return PatientState(
            patientId: id,
            mechanismOfInjury: "laceration",
            march: march,
            classification: .routine
        )
    }

    // --------------------------------------------------------------- empty

    func testEmptyPatientListReturnsBannerAndEmptyMessage() {
        let report = MedevacGenerator().generate(from: [])
        XCTAssertEqual(report.kind, .nineLine)
        XCTAssertTrue(report.isFallback)
        XCTAssertTrue(report.formattedText.contains(MedevacGenerator.fallbackBanner))
        XCTAssertTrue(report.formattedText.contains("No patients identified in assessment."))
    }

    // -------------------------------------------------------- single urgent

    func testSingleUrgentPatientAllLines() {
        let p = gswThighPatient()
        let report = MedevacGenerator().generate(from: [p])
        let text = report.formattedText

        XCTAssertTrue(text.hasPrefix(MedevacGenerator.fallbackBanner),
                      "Banner must lead the body")
        XCTAssertTrue(text.contains("\nLINE 1: MGRS UNKNOWN"))
        XCTAssertTrue(text.contains("\nLINE 2: 38.65 FM · DUSTOFF 6"))
        XCTAssertTrue(text.contains("\nLINE 3: 1 URGENT (A) / 0 PRIORITY (B) / 0 ROUTINE (C)"))
        // GSW thigh + tourniquet -> not a ventilator/hoist/extraction trigger
        XCTAssertTrue(text.contains("\nLINE 4: A-None"))
        // Litter because tourniquet on thigh
        XCTAssertTrue(text.contains("\nLINE 5: L1 · A0  ·  1 total"))
        XCTAssertTrue(text.contains("\nLINE 6: P · POSSIBLE ENEMY"))
        XCTAssertTrue(text.contains("\nLINE 7: C · SMOKE"))
        XCTAssertTrue(text.contains("\nLINE 8: A · US MIL"))
        XCTAssertTrue(text.contains("\nLINE 9: N · NONE"))
    }

    // -------------------------------------------------------- mixed lineup

    func testMixedTwoPatientsLine3AndLine5() {
        let urgent = gswThighPatient()
        let routine = minorLacerationPatient()
        let report = MedevacGenerator().generate(from: [urgent, routine])
        let text = report.formattedText

        XCTAssertTrue(text.contains("LINE 3: 1 URGENT (A) / 0 PRIORITY (B) / 1 ROUTINE (C)"))
        // Routine + alert + non-leg location => ambulatory
        XCTAssertTrue(text.contains("LINE 5: L1 · A1  ·  2 total"))
    }

    // -------------------------------------------------------- routine ambulatory

    func testSingleRoutineAmbulatoryPatient() {
        let p = minorLacerationPatient(id: "PATIENT_1")
        let report = MedevacGenerator().generate(from: [p])
        let text = report.formattedText
        XCTAssertTrue(text.contains("LINE 3: 0 URGENT (A) / 0 PRIORITY (B) / 1 ROUTINE (C)"))
        XCTAssertTrue(text.contains("LINE 5: L0 · A1  ·  1 total"))
    }

    // -------------------------------------------------------- priority count

    func testSinglePriorityPatient() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Alert"),
            classification: .priority
        )
        let report = MedevacGenerator().generate(from: [p])
        let text = report.formattedText
        XCTAssertTrue(text.contains("LINE 3: 0 URGENT (A) / 1 PRIORITY (B) / 0 ROUTINE (C)"))
    }

    // -------------------------------------------------------- urgent surgical

    func testUrgentSurgicalCollapsesIntoUrgentForLine3() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(
                respirationStatus: "tension pneumothorax",
                respirationIntervention: "Chest seal applied",
                consciousness: "Voice"
            ),
            classification: .urgentSurgical
        )
        let report = MedevacGenerator().generate(from: [p])
        let text = report.formattedText
        // Urgent + Urgent Surgical fold into the same Line 3 bucket.
        XCTAssertTrue(text.contains("LINE 3: 1 URGENT (A) / 0 PRIORITY (B) / 0 ROUTINE (C)"))
        XCTAssertTrue(text.contains("LINE 5: L1 · A0  ·  1 total"))
    }

    // -------------------------------------------------------- equipment

    func testIntubatedAirwayInfersVentilatorOnLine4() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(
                airwayIntervention: "Surgical cricothyroidotomy",
                consciousness: "Unresponsive"
            ),
            classification: .urgentSurgical
        )
        let report = MedevacGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("LINE 4: D-Ventilator"))
    }

    func testNoSpecialEquipmentDefaultIsANone() {
        let p = gswThighPatient()
        let report = MedevacGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("LINE 4: A-None"))
    }

    // -------------------------------------------------------- header overrides

    func testCustomCallsignAndFrequencyOnLine2() {
        let g = MedevacGenerator(callsign: "CHARLIE 5", frequency: "44.10 FM")
        let report = g.generate(from: [gswThighPatient()])
        XCTAssertTrue(report.formattedText.contains("\nLINE 2: 44.10 FM · CHARLIE 5"))
    }

    func testCustomLocationOnLine1() {
        let g = MedevacGenerator(location: "MGRS 38S MB 1234 5678")
        let report = g.generate(from: [gswThighPatient()])
        XCTAssertTrue(report.formattedText.contains("\nLINE 1: MGRS 38S MB 1234 5678"))
    }

    // -------------------------------------------------------- bilateral lower

    func testBilateralLowerExtremityIsLitter() {
        let march = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageLocation: "bilateral lower extremities",
            hemorrhageIntervention: "Junctional tourniquet",
            consciousness: "Voice"
        )
        let p = PatientState(
            patientId: "PATIENT_1",
            march: march,
            classification: .urgent
        )
        let report = MedevacGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("LINE 5: L1 · A0  ·  1 total"))
    }

    // -------------------------------------------------------- unconscious

    func testUnresponsivePatientIsLitter() {
        let p = PatientState(
            patientId: "PATIENT_1",
            march: MARCHState(consciousness: "Unresponsive"),
            classification: .urgent
        )
        let report = MedevacGenerator().generate(from: [p])
        XCTAssertTrue(report.formattedText.contains("LINE 5: L1 · A0  ·  1 total"))
    }

    // -------------------------------------------------------- report metadata

    func testReportMetadataIsFallbackAndKindNineLine() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let report = MedevacGenerator().generate(from: [gswThighPatient()], at: when)
        XCTAssertEqual(report.kind, .nineLine)
        XCTAssertTrue(report.isFallback)
        XCTAssertEqual(report.generatedAt, when)
    }

    // -------------------------------------------------------- mass casualty

    func testThreeUrgentPatientsCorrectCount() {
        let patients = [
            gswThighPatient(id: "PATIENT_1"),
            gswThighPatient(id: "PATIENT_2"),
            gswThighPatient(id: "PATIENT_3"),
        ]
        let report = MedevacGenerator().generate(from: patients)
        let text = report.formattedText
        XCTAssertTrue(text.contains("LINE 3: 3 URGENT (A) / 0 PRIORITY (B) / 0 ROUTINE (C)"))
        XCTAssertTrue(text.contains("LINE 5: L3 · A0  ·  3 total"))
    }
}
