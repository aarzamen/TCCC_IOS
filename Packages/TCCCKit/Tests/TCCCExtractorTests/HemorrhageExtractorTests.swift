// HemorrhageExtractorTests
//
// Parity tests for `HemorrhageExtractor` against `_extract_hemorrhage` from
// /Users/ama/TCCC_FEB_2026/src/state.py:579–661. Truth values were captured
// by running the Python implementation directly against each input string.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class HemorrhageExtractorTests: XCTestCase {

    private let h = HemorrhageExtractor()

    private func freshContext(
        _ sentence: String, isNegated: Bool = false
    ) -> ExtractionContext {
        ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(timeIntervalSince1970: 0),
            currentPatientID: "PATIENT_1",
            isNegated: isNegated)
    }

    // MARK: - Identification

    func testBleedingFromRightThighIdentifies() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "I can see significant bleeding from the right thigh area."))
        XCTAssertTrue(s.march.hemorrhageIdentified)
        XCTAssertTrue(s.march.hemorrhageAssessed)
        XCTAssertEqual(s.march.hemorrhageLocation, "right thigh")
    }

    func testGsAttribsHemorrhageContextEvenWithoutBleed() {
        // "GSW" appears in the hemorrhage context-word list, so a sided body
        // part anchored by GSW gets a location.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GSW to the right upper thigh."))
        XCTAssertEqual(s.march.hemorrhageLocation, "right upper thigh")
    }

    func testHemorrhageWordIdentifies() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Massive hemorrhage from the abdomen."))
        XCTAssertTrue(s.march.hemorrhageIdentified)
        XCTAssertEqual(s.march.hemorrhageLocation, "abdomen")
    }

    // MARK: - Negative bleeding pre-pass

    func testNoExternalBleedingMarksAssessedNotIdentifiedThroughNegativeRegex() {
        // "no external bleeding" matches the dedicated negative regex.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("no external bleeding observed."))
        XCTAssertTrue(s.march.hemorrhageAssessed)
        XCTAssertFalse(s.march.hemorrhageIdentified)
    }

    func testNoBleedingMarksAssessed() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("no bleeding seen."))
        XCTAssertTrue(s.march.hemorrhageAssessed)
        XCTAssertFalse(s.march.hemorrhageIdentified)
    }

    func testNoActiveBleedMarksAssessed() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("no active bleed at this time."))
        XCTAssertTrue(s.march.hemorrhageAssessed)
        XCTAssertFalse(s.march.hemorrhageIdentified)
    }

    func testNoBloodMarksAssessed() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("no blood pooling."))
        XCTAssertTrue(s.march.hemorrhageAssessed)
        XCTAssertFalse(s.march.hemorrhageIdentified)
    }

    // MARK: - Tourniquet detection

    func testCATTourniquetSetsIntervention() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("CAT tourniquet right thigh, high and tight."))
        XCTAssertNotNil(s.march.hemorrhageIntervention)
        XCTAssertTrue(s.march.hemorrhageIntervention!.lowercased().contains("tourniquet"))
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .tourniquet)
    }

    func testTourniquetIncludesLocationWhenKnown() {
        var initial = PatientState(patientId: "PATIENT_1")
        initial.march.hemorrhageLocation = "right thigh"
        let s = h.apply(initial,
                        context: freshContext("Applying tourniquet to the right leg."))
        XCTAssertEqual(s.march.hemorrhageIntervention, "Tourniquet applied (right thigh)")
    }

    func testNoTourniquetNeededDoesNotSetIntervention() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("No tourniquet needed at this time."))
        XCTAssertNil(s.march.hemorrhageIntervention)
        XCTAssertTrue(s.interventions.isEmpty)
    }

    func testTonicaineDoesNotMatchTonic() {
        // "tonicaine" is the regex's documented false-positive guard.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pre-medicated with tonicaine."))
        XCTAssertNil(s.march.hemorrhageIntervention)
    }

    // MARK: - Pressure dressing

    func testPressureDressingDetected() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Applying pressure dressing."))
        XCTAssertEqual(s.march.hemorrhageIntervention, "Pressure dressing applied")
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .pressureDressing)
    }

    func testTourniquetWinsOverPressureDressing() {
        // Both patterns may match; tourniquet branch runs first and sets
        // intervention. Pressure dressing only sets if intervention is nil.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "Applying tourniquet first, then pressure dressing on top."))
        XCTAssertEqual(s.march.hemorrhageIntervention?.lowercased().contains("tourniquet"),
                       true)
    }

    // MARK: - Controlled

    func testControlledSetsEffective() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Bleeding controlled with pressure."))
        XCTAssertEqual(s.march.hemorrhageEffective, true)
    }

    func testStoppedSetsEffective() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Bleeding has stopped."))
        XCTAssertEqual(s.march.hemorrhageEffective, true)
    }

    // MARK: - Location patterns

    func testBilateralLowerExtremityLocation() {
        // Python: "bilateral {group(2) if group(2) else 'extremity'}"
        // For "bilateral lower extremity injuries" group(2) = "extremity".
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "This patient has bilateral lower extremity injuries, both legs are bleeding heavily."))
        XCTAssertNotNil(s.march.hemorrhageLocation)
        XCTAssertTrue(s.march.hemorrhageLocation!.contains("bilateral"))
    }

    func testBothLegsLocation() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("both legs are bleeding."))
        XCTAssertNotNil(s.march.hemorrhageLocation)
        XCTAssertTrue(s.march.hemorrhageLocation!.contains("bilateral"))
    }

    func testRightThighLocation() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Significant bleeding from the right thigh."))
        XCTAssertEqual(s.march.hemorrhageLocation, "right thigh")
    }

    func testForearmLacerationLocation() {
        // "laceration" is in the hemorrhage context-word list, so the general
        // body-part pattern picks up "forearm".
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("laceration to the right forearm."))
        XCTAssertNotNil(s.march.hemorrhageLocation)
        XCTAssertTrue(s.march.hemorrhageLocation!.contains("forearm"))
    }

    // MARK: - Context-word gating
    //
    // The location pass only runs when the sentence contains one of the
    // hemorrhage CONTEXT words. A bare body-part mention with no bleed/wound
    // word in scope does NOT populate hemorrhageLocation.

    func testBodyPartAloneDoesNotSetLocation() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("His right thigh is visibly deformed."))
        // No "bleed/blood/hemorrhag/wound/injury" word -> no location.
        XCTAssertNil(s.march.hemorrhageLocation)
    }

    // MARK: - Scenario-derived assertions
    //
    // Mirror the assertions in test_state_scenarios.py for the scenarios this
    // extractor governs (wrapping Python's PatientStateEngine.update calls).

    func testScenario1FullFlowYieldsTourniquet() {
        // Scenario 1 sequence (sentences from scenario_1_gsw_thigh.txt):
        var state = PatientState(patientId: "PATIENT_1")
        let sentences = [
            "I can see significant bleeding from the right thigh area.",
            "Looks like a gunshot wound to the right upper thigh.",
            "Applying a tourniquet now, CAT tourniquet, right thigh, high and tight.",
            "Okay tourniquet is on, bleeding appears controlled.",
        ]
        for sentence in sentences {
            state = h.apply(state, context: freshContext(sentence))
        }
        XCTAssertTrue(state.march.hemorrhageIdentified)
        XCTAssertNotNil(state.march.hemorrhageIntervention)
        XCTAssertTrue(
            state.march.hemorrhageIntervention!.lowercased().contains("tourniquet"))
        XCTAssertEqual(state.march.hemorrhageEffective, true)
    }

    func testScenario2Patient2ForearmAndPressureDressing() {
        var state = PatientState(patientId: "PATIENT_2")
        let sentences = [
            "This patient is alert and talking, has a laceration to the right forearm, moderate bleeding.",
            "Applying pressure dressing.",
            "No tourniquet needed at this time.",
        ]
        for sentence in sentences {
            state = h.apply(state, context: freshContext(sentence))
        }
        XCTAssertNotNil(state.march.hemorrhageLocation)
        XCTAssertTrue(state.march.hemorrhageLocation!.lowercased().contains("forearm"))
        XCTAssertNotNil(state.march.hemorrhageIntervention)
        XCTAssertTrue(
            state.march.hemorrhageIntervention!.lowercased().contains("pressure dressing"))
    }

    func testScenario4NoTourniquetNeeded() {
        // Scenario 4 explicitly negates the TQ ("no tourniquet needed").
        var state = PatientState(patientId: "PATIENT_1")
        let sentences = [
            "I don't see any external bleeding.",
            "His right thigh is visibly deformed, swollen.",
            "No open wound though, so no tourniquet needed at this time.",
        ]
        for sentence in sentences {
            state = h.apply(state, context: freshContext(sentence))
        }
        let intervention = (state.march.hemorrhageIntervention ?? "").lowercased()
        XCTAssertFalse(intervention.contains("tourniquet"),
                       "Scenario 4 negates tourniquet; should not appear in hemorrhage intervention")
    }

    // MARK: - Bilateral inference (right + left across sentences)

    func testRightLegThenLeftLegMergesToBilateral() {
        var state = PatientState(patientId: "PATIENT_1")
        state = h.apply(
            state,
            context: freshContext("Bleeding on the right leg."))
        XCTAssertEqual(state.march.hemorrhageLocation, "right leg")
        state = h.apply(
            state,
            context: freshContext("Now the left leg is bleeding too."))
        XCTAssertNotNil(state.march.hemorrhageLocation)
        XCTAssertTrue(state.march.hemorrhageLocation!.contains("bilateral"))
        XCTAssertTrue(state.march.hemorrhageLocation!.contains("legs"))
    }

    // MARK: - Tourniquet appended to interventions list once

    func testTourniquetNotDuplicatedInInterventions() {
        var state = PatientState(patientId: "PATIENT_1")
        state = h.apply(
            state,
            context: freshContext("Applying tourniquet to right thigh."))
        state = h.apply(
            state,
            context: freshContext("Tightening the tourniquet now."))
        let tqInterventions = state.interventions.filter { $0.kind == .tourniquet }
        XCTAssertEqual(tqInterventions.count, 1)
    }
}
