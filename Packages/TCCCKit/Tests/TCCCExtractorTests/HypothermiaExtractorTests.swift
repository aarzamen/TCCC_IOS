// HypothermiaExtractorTests
//
// Half of the 2026 split of HeadHypothermiaExtractorTests — hypothermia
// prevention only. Mirrors the Python prototype's `_extract_head_hypothermia`
// hypothermia branch.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class HypothermiaExtractorTests: XCTestCase {

    private let h = HypothermiaExtractor()

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

    func testHypothermiaPhaseStatusReflectsField() {
        var state = PatientState(patientId: "PATIENT_1")
        XCTAssertEqual(state.march.hypothermiaPhaseStatus, .notAssessed)
        state = h.apply(state, context: freshContext("Apply a hypothermia wrap."))
        XCTAssertEqual(state.march.hypothermiaPhaseStatus, .done)
    }

    func testUnrelatedSentenceLeavesHypothermiaUnchanged() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("It's a sunny afternoon."))
        XCTAssertNil(s.march.hypothermiaPrevention)
        XCTAssertTrue(s.interventions.isEmpty)
    }

    // Hypothermia extractor must not mutate AVPU / pupils / GCS — those
    // are TBIExtractor's responsibility post-2026 split.
    func testHypothermiaIgnoresAvpuPupilsGcs() {
        let s = h.apply(
            PatientState(patientId: "PATIENT_1"),
            context: freshContext("Patient is alert, pupils equal, GCS 15. Apply hypothermia wrap."))
        XCTAssertEqual(s.march.hypothermiaPrevention, "Hypothermia wrap applied")
        XCTAssertNil(s.march.consciousness)
        XCTAssertNil(s.march.pupilResponse)
        XCTAssertNil(s.vitals.gcs)
    }
}
