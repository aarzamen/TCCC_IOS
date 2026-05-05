// ValidatorFallbackHeuristicTests
//
// Verifies the >40% line-rewrite heuristic that the app-target generators
// (`RadioScriptGenerator`, `ZMISTNarrativeGenerator`) use to decide whether
// to drop SLM output and fall back to the deterministic generator.
//
// The generators themselves live in the app target and so cannot be imported
// here, but the heuristic is a pure function over (raw, validated) strings.
// We replicate it locally and assert that a deliberately-bogus SLM output
// produces a validator delta large enough to trigger the fallback path.
//
// Mirrors the contract documented in
// docs/superpowers/plans/2026-05-05-review-hardening.md (Task B5).

import XCTest
@testable import TCCCReports
import TCCCDomain

final class ValidatorFallbackHeuristicTests: XCTestCase {

    // MARK: - Local copy of the generator-side heuristic

    /// Returns true when the validator rewrote / removed > 40% of distinct
    /// lines. Identical to the implementation in
    /// `TCCC_IOS/Intelligence/RadioScriptGenerator.swift` and
    /// `TCCC_IOS/Intelligence/ZMISTNarrativeGenerator.swift`.
    private func validationFailed(raw: String, validated: String) -> Bool {
        let rawLines = Set(raw.split(separator: "\n").map(String.init))
        let valLines = Set(validated.split(separator: "\n").map(String.init))
        let total = rawLines.count
        guard total > 0 else { return true }
        let changed = rawLines.symmetricDifference(valLines).count
        return Double(changed) / Double(total) > 0.4
    }

    // MARK: - Fixtures

    private func urgentTQPatient() -> PatientState {
        return PatientState(
            patientId: "PATIENT_1",
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
            classification: .urgent
        )
    }

    // MARK: - MEDEVAC fallback path

    /// Bogus SLM output: every targeted line (3, 4, 5) is wrong AND there is
    /// no pass-through content. Validator rewrites all three. Heuristic must
    /// fire (3 of 3 lines changed > 40%).
    func testMedevac_majorityLinesRewritten_triggersFallback() {
        let bogus = """
        Line 3 (Precedence):     A-99, B-99, C-99, D-99, E-99
        Line 4 (Special Equip):  Helicopter & Hoist & Ventilator & Oxygen
        Line 5 (# Patients):     A-Litter: 99, B-Ambulatory: 99
        """
        let patients = [urgentTQPatient()]

        let validated = MedevacValidator.validate(
            bogus,
            against: patients,
            transcript: ""
        )

        // Sanity: the validator did rewrite the lines.
        XCTAssertNotEqual(validated, bogus)
        XCTAssertTrue(validated.contains("A-1, B-0, C-0, D-0, E-0"))
        XCTAssertTrue(validated.contains("A-Litter: 1, B-Ambulatory: 0"))

        // The heuristic must consider this a failure → caller should fall back.
        XCTAssertTrue(
            validationFailed(raw: bogus, validated: validated),
            "All-bogus 3-line input should trip the >40% rewrite heuristic"
        )
    }

    /// Pass-through lines (1, 2, 6–9) should keep the rewrite ratio below the
    /// 40% threshold even when the targeted lines are wrong, because the
    /// SLM output is mostly fine.
    func testMedevac_minorRewrite_doesNotTriggerFallback() {
        let raw = """
        9-LINE MEDEVAC REQUEST
        =====================
        Line 1 (Location):       MGRS 12ABC34567890
        Line 2 (Frequency):      38.65 FM, callsign DUSTOFF 6
        Line 3 (Precedence):     A-99, B-0, C-0, D-0, E-0
        Line 4 (Special Equip):  Hoist
        Line 5 (# Patients):     A-Litter: 1, B-Ambulatory: 0
        Line 6 (Security):       N-No enemy
        Line 7 (Marking):        C-Smoke
        Line 8 (Nationality):    A-US Military
        Line 9 (CBRN):           N-No CBRN
        """
        let patients = [urgentTQPatient()]

        let validated = MedevacValidator.validate(
            raw,
            against: patients,
            transcript: ""
        )

        // The validator should only rewrite Line 3 (urgent count was wrong).
        // 1 changed line of ~11 distinct lines → well under 40%.
        XCTAssertFalse(
            validationFailed(raw: raw, validated: validated),
            "Single-line correction in an otherwise-valid MEDEVAC must not fall back"
        )
    }

    // MARK: - ZMIST fallback path

    /// SLM output that fabricates injuries / signs / treatment / evacuation —
    /// each in its own line — and presents them in the standard ZMIST field-
    /// header form so the validator actually picks them up. All four targeted
    /// fields get rewritten; the heuristic should fire.
    func testZMIST_fabricatedBlock_triggersFallback() {
        let bogus = """
        ZMIST CASUALTY REPORT
        =====================
        Z (Zap #):       PATIENT_1
        M (Mechanism):   Pedestrian struck by vehicle.
        I (Injuries):    Bilateral femur fractures, flail chest, decapitation.
        S (Signs):       HR 180, BP 60/40, SpO2 70, RR 6.
        T (Treatment):   Bilateral chest seals, needle decompression x2, blood x4.
        Evacuation:      URGENT SURGICAL
        Classification:  URGENT_SURGICAL
        """
        let patients = [urgentTQPatient()]

        let validated = ZMISTValidator.validate(bogus, against: patients)

        // Validator should have replaced the fabricated targeted lines.
        XCTAssertNotEqual(validated, bogus)
        XCTAssertFalse(validated.contains("decapitation"))
        XCTAssertFalse(validated.contains("HR 180"))
        XCTAssertTrue(validated.contains("HR 110"))

        // 4 of ~8 distinct lines rewritten → ratio is ≥ 0.4.  Plus the
        // validator inserts blank lines / classification rewrite, so the
        // heuristic comfortably fires.
        XCTAssertTrue(
            validationFailed(raw: bogus, validated: validated),
            "Wholesale fabrication should trip the >40% rewrite heuristic"
        )
    }

    // MARK: - Empty-output guard

    func testEmptyRawOutput_alwaysTriggersFallback() {
        XCTAssertTrue(validationFailed(raw: "", validated: ""))
    }
}
