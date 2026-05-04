// HeadHypothermiaExtractorTests
//
// Parity tests for `HeadHypothermiaExtractor` against `_extract_head_hypothermia`
// from /Users/ama/TCCC_FEB_2026/src/state.py:766–797. Truth values captured
// by running Python's PatientStateEngine.update_from_transcript directly.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class HeadHypothermiaExtractorTests: XCTestCase {

    private let h = HeadHypothermiaExtractor()

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
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testOriented() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is oriented."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testAlertAndOriented() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert and oriented."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testAandO() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is A and O."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    func testRespondsToVoice() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Responds to voice."))
        XCTAssertEqual(s.march.consciousness, "Voice")
    }

    func testVoiceResponsive() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is voice responsive."))
        XCTAssertEqual(s.march.consciousness, "Voice")
    }

    func testRespondsToPain() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Responds to pain only."))
        XCTAssertEqual(s.march.consciousness, "Pain")
    }

    func testPainResponsive() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is pain responsive."))
        XCTAssertEqual(s.march.consciousness, "Pain")
    }

    func testUnresponsive() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is unresponsive."))
        XCTAssertEqual(s.march.consciousness, "Unresponsive")
    }

    func testUnconscious() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is unconscious."))
        XCTAssertEqual(s.march.consciousness, "Unresponsive")
    }

    func testAlertWinsOverOtherAvpuWhenBothPresent() {
        // Python iterates and breaks on first match; "alert" comes first.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert but responds to voice only."))
        XCTAssertEqual(s.march.consciousness, "Alert")
    }

    // MARK: - Pupils

    func testPupilsEqual() {
        // Basic regex captures group(2) = "equal".
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils equal and reactive."))
        XCTAssertEqual(s.march.pupilResponse, "equal")
    }

    func testPupilsAreEqual() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils are equal."))
        XCTAssertEqual(s.march.pupilResponse, "equal")
    }

    func testPupilsDilated() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils dilated."))
        XCTAssertEqual(s.march.pupilResponse, "dilated")
    }

    func testPupilsConstricted() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils constricted bilaterally."))
        XCTAssertEqual(s.march.pupilResponse, "constricted")
    }

    func testPupilsFixed() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils fixed."))
        XCTAssertEqual(s.march.pupilResponse, "fixed")
    }

    func testPupilsUnequal() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Pupils unequal."))
        XCTAssertEqual(s.march.pupilResponse, "unequal")
    }

    // MARK: - Hypothermia prevention

    func testHypothermiaWrap() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Apply a hypothermia wrap."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
        XCTAssertEqual(s.interventions.count, 1)
        XCTAssertEqual(s.interventions.first?.kind, .hypothermiaPrevention)
        XCTAssertEqual(
            s.interventions.first?.description,
            "Hypothermia prevention measures")
    }

    func testPreventHypothermia() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Wrapping the patient to prevent hypothermia."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testWrappingMatchesHypothermia() {
        // The pattern includes "wrapping" as a standalone trigger.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Wrapping him up to stay warm."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testBlanketMatchesHypothermia() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Covered with a blanket."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testInsulateMatchesHypothermia() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Insulate from the cold ground."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testHypothermiaNotDuplicatedInInterventions() {
        var state = PatientState(patientId: "PATIENT_1")
        state = h.apply(
            state,
            context: freshContext("Apply a hypothermia wrap."))
        state = h.apply(
            state,
            context: freshContext("Wrapping him up to prevent hypothermia."))
        let hypoInterventions = state.interventions.filter {
            $0.kind == .hypothermiaPrevention
        }
        XCTAssertEqual(hypoInterventions.count, 1)
    }

    // MARK: - GCS

    func testGcsDigits() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS 15."))
        XCTAssertEqual(s.vitals.gcs, 15)
    }

    func testGcsIs() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS is 13."))
        XCTAssertEqual(s.vitals.gcs, 13)
    }

    func testGcsOf() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS of 8."))
        XCTAssertEqual(s.vitals.gcs, 8)
    }

    func testGcsSpokenWordIsNotMatched() {
        // Mirrors the SpokenNumberNormalizer "GCS fifteen" non-clinical
        // passthrough — without normalization, GCS spoken-word is left alone.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS fifteen."))
        XCTAssertNil(s.vitals.gcs)
    }

    func testGcsOutOfRangeDropped() {
        // Vitals.gcsRange is 3...15. Out-of-range values are dropped.
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("GCS 99."))
        XCTAssertNil(s.vitals.gcs)
    }

    // MARK: - Composite + scenario

    func testScenario1HeadCheckYieldsAlertPlusEqualPlusHypothermia() {
        var state = PatientState(patientId: "PATIENT_1")
        let sentences = [
            "Patient is alert, oriented, pupils equal and reactive.",
            "Wrapping the patient to prevent hypothermia.",
        ]
        for sentence in sentences {
            state = h.apply(state, context: freshContext(sentence))
        }
        XCTAssertEqual(state.march.consciousness, "Alert")
        XCTAssertEqual(state.march.pupilResponse, "equal")
        XCTAssertEqual(state.march.hypothermiaPrevention, "Hypothermia wrap applied")
    }

    func testScenario4GcsAndAvpu() {
        // Scenario 4: "He's alert, oriented, GCS fifteen."
        // Note: scenario 4's GCS is "fifteen" spoken-form, which the engine
        // depends on the normalizer to convert. At the extractor layer alone,
        // only the digit form sets vitals.gcs. We assert the typical
        // engine-level outcome by feeding the digit form here.
        var state = PatientState(patientId: "PATIENT_1")
        state = h.apply(
            state,
            context: freshContext("He's alert, oriented, GCS 15."))
        state = h.apply(
            state,
            context: freshContext("Pupils equal and reactive."))
        XCTAssertEqual(state.march.consciousness, "Alert")
        XCTAssertEqual(state.march.pupilResponse, "equal")
        XCTAssertEqual(state.vitals.gcs, 15)
    }

    // MARK: - No-op

    func testUnrelatedSentenceLeavesStateUnchanged() {
        let initial = PatientState(patientId: "PATIENT_1")
        let s = h.apply(
            initial,
            context: freshContext("It's a sunny afternoon."))
        XCTAssertNil(s.march.consciousness)
        XCTAssertNil(s.march.pupilResponse)
        XCTAssertNil(s.march.hypothermiaPrevention)
        XCTAssertNil(s.vitals.gcs)
        XCTAssertTrue(s.interventions.isEmpty)
    }
}
