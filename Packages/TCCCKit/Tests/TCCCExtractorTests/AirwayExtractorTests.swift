// AirwayExtractorTests
//
// Parity tests for `AirwayExtractor` against `_extract_airway` from
// /Users/ama/TCCC_FEB_2026/src/state.py:663–681. Truth values were captured
// by running Python's `PatientStateEngine.update_from_transcript` directly
// against each input string.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class AirwayExtractorTests: XCTestCase {

    private let a = AirwayExtractor()

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

    // MARK: - Patent

    func testAirwayIsPatent() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is patent."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    func testAirwayClear() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway clear."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    func testAirwayOpen() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is open."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    func testTalkingTreatedAsPatent() {
        // The "patent" regex includes "talking" as a positive marker.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is talking to me."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    func testConsciousAndTalkingTreatedAsPatent() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is conscious, talking to me, airway is patent."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    // MARK: - Compromised

    func testAirwayCompromised() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is compromised."))
        XCTAssertEqual(s.march.airwayStatus, "compromised")
    }

    func testAirwayObstructed() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is obstructed."))
        XCTAssertEqual(s.march.airwayStatus, "compromised")
    }

    func testAirwayBlocked() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is blocked."))
        XCTAssertEqual(s.march.airwayStatus, "compromised")
    }

    func testPatentWinsOverCompromisedWhenBothMatch() {
        // Python uses if/elif: patent branch wins. A sentence with both
        // "patent" and "compromise" words still resolves to "patent".
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "Airway is patent, no compromise observed."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    // MARK: - Interventions: NPA

    func testNpaSetsIntervention() {
        // Note: "recovery position" is recognized as a separate 2026 §4
        // intervention by AirwayExtractor — the original sentence
        // "Inserting NPA, placing in recovery position." now produces TWO
        // interventions. This test isolates the NPA event by using a
        // sentence with only NPA vocabulary.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Inserting NPA in the right nostril."))
        XCTAssertEqual(s.march.airwayIntervention, "NPA inserted")
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .npa)
        XCTAssertEqual(s.interventions.first?.description, "NPA inserted")
    }

    func testNasopharyngealMatchesNpa() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Placed nasopharyngeal airway."))
        XCTAssertEqual(s.march.airwayIntervention, "NPA inserted")
    }

    func testNasalAirwayMatchesNpa() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Inserted nasal airway."))
        XCTAssertEqual(s.march.airwayIntervention, "NPA inserted")
    }

    // MARK: - Interventions: Cric

    func testCricSetsIntervention() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Performing surgical cricothyroidotomy."))
        XCTAssertEqual(s.march.airwayIntervention, "Surgical cricothyroidotomy")
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .surgicalAirway)
    }

    func testSurgicalAirwayMatchesCric() {
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Surgical airway in place."))
        XCTAssertEqual(s.march.airwayIntervention, "Surgical cricothyroidotomy")
    }

    func testNpaWinsOverCricWhenBothMatch() {
        // Python uses if/elif: NPA branch wins.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("NPA inserted while preparing cric."))
        XCTAssertEqual(s.march.airwayIntervention, "NPA inserted")
    }

    // MARK: - Idempotence (no duplicate interventions)

    func testNpaNotDuplicated() {
        var state = PatientState(patientId: "PATIENT_1")
        state = a.apply(state, context: freshContext("Inserting NPA."))
        state = a.apply(state, context: freshContext("Securing NPA in place."))
        let npaInterventions = state.interventions.filter { $0.kind == .npa }
        XCTAssertEqual(npaInterventions.count, 1)
    }

    func testCricNotDuplicated() {
        var state = PatientState(patientId: "PATIENT_1")
        state = a.apply(state, context: freshContext("Performed cric."))
        state = a.apply(state, context: freshContext("Cric in place."))
        let cricInterventions = state.interventions.filter { $0.kind == .surgicalAirway }
        XCTAssertEqual(cricInterventions.count, 1)
    }

    // MARK: - Negation behavior
    //
    // Python's _extract_airway does NOT consult `has_negated_finding`. We
    // mirror that. context.isNegated is informational; the regex constructs
    // already encode positive language.

    func testNegationFlagDoesNotSuppressPatentRegex() {
        // Even if isNegated=true, "airway is patent" still sets status.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Airway is patent.", isNegated: true))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    // MARK: - No-op cases

    func testUnrelatedSentenceLeavesStateUnchanged() {
        let initial = PatientState(patientId: "PATIENT_1")
        let s = a.apply(
            initial,
            context: freshContext("The sky is blue today."))
        XCTAssertNil(s.march.airwayStatus)
        XCTAssertNil(s.march.airwayIntervention)
        XCTAssertTrue(s.interventions.isEmpty)
    }

    // MARK: - Scenario assertions

    func testScenario1AirwayPatent() {
        // Mirrors expected behavior on scenario_1_gsw_thigh.txt's airway sentence.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "Patient is conscious, talking to me, airway is patent."))
        XCTAssertEqual(s.march.airwayStatus, "patent")
    }

    func testScenario2Patient1NpaInserted() {
        // Mirror test_scenario2_patient1_npa from
        // /Users/ama/TCCC_FEB_2026/tests/test_state_scenarios.py:114–119.
        let s = a.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext(
                "Airway on casualty one, patient is unconscious but breathing. " +
                "Inserting NPA, placing in recovery position."))
        XCTAssertNotNil(s.march.airwayIntervention)
        XCTAssertTrue(s.march.airwayIntervention!.lowercased().contains("npa"))
    }
}
