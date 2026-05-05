// TBIExtractorTests
//
// Half of the 2026 split of HeadHypothermiaExtractorTests — AVPU, pupils,
// and GCS only. Mirrors the Python prototype's `_extract_head_hypothermia`
// AVPU/pupils/GCS branches.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class TBIExtractorTests: XCTestCase {

    private let t = TBIExtractor()

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

    // MARK: - AVPU

    func testAlert() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testOriented() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is oriented."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testAlertAndOriented() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert and oriented."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testAandO() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is A and O."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testRespondsToVoice() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Responds to voice."))
        XCTAssertEqual(s.march.consciousness, "Voice")
    }

    func testVoiceResponsive() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is voice responsive."))
        XCTAssertEqual(s.march.consciousness, "Voice")
    }

    func testRespondsToPain() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Responds to pain only."))
        XCTAssertEqual(s.march.consciousness, "Pain")
    }

    func testPainResponsive() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is pain responsive."))
        XCTAssertEqual(s.march.consciousness, "Pain")
    }

    func testUnresponsive() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is unresponsive."))
        XCTAssertEqual(s.march.consciousness, "Unresponsive")
    }

    func testUnconscious() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is unconscious."))
        XCTAssertEqual(s.march.consciousness, "Unresponsive")
    }

    func testAlertWinsOverOtherAvpuWhenBothPresent() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert but responds to voice only."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    // MARK: - Pupils

    func testPupilsEqual() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils equal and reactive."))
        XCTAssertEqual(s.march.pupilResponse, "equal")
    }

    func testPupilsAreEqual() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils are equal."))
        XCTAssertEqual(s.march.pupilResponse, "equal")
    }

    func testPupilsDilated() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils dilated."))
        XCTAssertEqual(s.march.pupilResponse, "dilated")
    }

    func testPupilsConstricted() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils constricted bilaterally."))
        XCTAssertEqual(s.march.pupilResponse, "constricted")
    }

    func testPupilsFixed() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils fixed."))
        XCTAssertEqual(s.march.pupilResponse, "fixed")
    }

    func testPupilsUnequal() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils unequal."))
        XCTAssertEqual(s.march.pupilResponse, "unequal")
    }

    // MARK: - GCS

    func testGcsDigits() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS 15."))
        XCTAssertEqual(s.vitals.gcs, 15)
    }

    func testGcsIs() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS is 13."))
        XCTAssertEqual(s.vitals.gcs, 13)
    }

    func testGcsOf() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS of 8."))
        XCTAssertEqual(s.vitals.gcs, 8)
    }

    func testGcsSpokenWordIsNotMatched() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS fifteen."))
        XCTAssertNil(s.vitals.gcs)
    }

    func testGcsOutOfRangeDropped() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS 99."))
        XCTAssertNil(s.vitals.gcs)
    }

    // MARK: - Phase status

    func testTbiPhaseStatusReflectsConsciousness() {
        var state = PatientState(patientId: "PATIENT_1")
        XCTAssertEqual(state.march.tbiPhaseStatus, .notAssessed)
        state = t.apply(state, context: freshContext("Patient is alert."))
        XCTAssertEqual(state.march.tbiPhaseStatus, .done)
    }

    func testTbiPhaseStatusReflectsPupils() {
        var state = PatientState(patientId: "PATIENT_1")
        state = t.apply(state, context: freshContext("Pupils equal."))
        XCTAssertEqual(state.march.tbiPhaseStatus, .done)
    }

    // MARK: - Composite + scenario

    func testScenario1HeadCheckYieldsAlertPlusEqual() {
        var state = PatientState(patientId: "PATIENT_1")
        let sentences = [
            "Patient is alert, oriented, pupils equal and reactive.",
        ]
        for sentence in sentences {
            state = t.apply(state, context: freshContext(sentence))
        }
        XCTAssertEqual(state.march.consciousness, "Alert")
        XCTAssertEqual(state.march.pupilResponse, "equal")
    }

    func testScenario4GcsAndAvpu() {
        var state = PatientState(patientId: "PATIENT_1")
        state = t.apply(
            state,
            context: freshContext("He's alert, oriented, GCS 15."))
        state = t.apply(
            state,
            context: freshContext("Pupils equal and reactive."))
        XCTAssertEqual(state.march.consciousness, "Alert")
        XCTAssertEqual(state.march.pupilResponse, "equal")
        XCTAssertEqual(state.vitals.gcs, 15)
    }

    // TBI extractor must not mutate hypothermia — that is HypothermiaExtractor's
    // responsibility post-2026 split.
    func testTbiIgnoresHypothermia() {
        let s = t.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Wrapping the patient to prevent hypothermia. Patient is alert."))
        XCTAssertEqual(s.march.consciousness, "Alert")
        XCTAssertNil(s.march.hypothermiaPrevention)
    }

    func testUnrelatedSentenceLeavesStateUnchanged() {
        let initial = PatientState(patientId: "PATIENT_1")
        let s = t.apply(
            initial,
            context: freshContext("It's a sunny afternoon."))
        XCTAssertNil(s.march.consciousness)
        XCTAssertNil(s.march.pupilResponse)
        XCTAssertNil(s.vitals.gcs)
    }
}
