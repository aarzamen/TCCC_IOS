// ClassificationExtractorTests
//
// Mirrors the Python classification assertions from
// /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py (TestClassificationNegation)
// and tests/test_state_scenarios.py (the four scenario classification cases).
//
// Covers both code paths inside ClassificationExtractor:
//
//   1. Explicit per-sentence classification (state.py:_extract_classification,
//      lines 822–855), including the negated-urgent override path.
//   2. Inferred classification from clinical findings
//      (state.py:infer_classification, lines 931–1028).

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class ClassificationExtractorTests: XCTestCase {

    private let extractor = ClassificationExtractor()

    private func ctx(
        _ sentence: String,
        isNegated: Bool = false
    ) -> ExtractionContext {
        return ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(timeIntervalSince1970: 0),
            currentPatientID: "PATIENT_1",
            isNegated: isNegated
        )
    }

    private func emptyState() -> PatientState {
        return PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Explicit classification (state.py:822–855)

    func testExplicitUrgent() {
        // Python regression: "This is an urgent casualty, possible femur fracture..."
        let s = extractor.apply(
            emptyState(),
            context: ctx("This is an urgent casualty, possible femur fracture, " +
                         "internal bleeding risk."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testExplicitUrgentSurgical() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("This is urgent surgical, get them on a bird now."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testExplicitUrgentSurgicalAlternateNeedsSurgery() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Patient needs surgery within the hour."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testExplicitPriority() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("This is a priority patient, walking wounded."))
        XCTAssertEqual(s.classification, .priority)
    }

    func testExplicitRoutine() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("This is a routine casualty. He can walk himself " +
                         "to the aid station."))
        XCTAssertEqual(s.classification, .routine)
    }

    func testExplicitWalkingWoundedRoutine() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Walking wounded, send him over."))
        XCTAssertEqual(s.classification, .routine)
    }

    func testExplicitExpectant() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Casualty is expectant — unsurvivable injuries."))
        XCTAssertEqual(s.classification, .expectant)
    }

    // MARK: - Negation override (state.py:838–852, P2 fix)

    func testNothingUrgentNotClassifiedUrgent() {
        // Python TestClassificationNegation.test_nothing_urgent_not_classified_urgent
        let s = extractor.apply(
            emptyState(),
            context: ctx("nothing urgent, walking wounded."))
        XCTAssertNotEqual(s.classification, .urgent)
        XCTAssertNotEqual(s.classification, .urgentSurgical)
        XCTAssertEqual(s.classification, .routine,
                       "Walking-wounded should classify Routine when urgency is negated")
    }

    func testNothingUrgentRoutineCasualtyOverride() {
        // Python TestClassificationNegation.test_nothing_urgent_with_explicit_routine
        let s = extractor.apply(
            emptyState(),
            context: ctx("Probably needs a few stitches but nothing urgent. " +
                         "This is a routine casualty."))
        XCTAssertEqual(s.classification, .routine)
    }

    func testNotUrgentClassifiedAsRoutineWithExplicit() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("This is not urgent, this is a routine evac."))
        XCTAssertEqual(s.classification, .routine)
    }

    func testNotUrgentClassifiedAsPriorityWithExplicit() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Not urgent, this is a priority casualty."))
        XCTAssertEqual(s.classification, .priority)
    }

    // MARK: - Inferred classification (state.py:931–1028)
    //
    // For the inferred path, build a PatientState whose vitals and MARCH
    // fields are already populated (as they would be after the other
    // extractors had run), then apply ClassificationExtractor with a
    // sentence that contains no explicit classification language.

    func testInferUrgentSurgicalGCS8() {
        var st = emptyState()
        st.vitals = Vitals(gcs: 8)
        let s = extractor.apply(st, context: ctx("Patient is unresponsive."))
        XCTAssertEqual(s.classification, .urgentSurgical,
                       "GCS ≤ 8 → Urgent Surgical")
    }

    func testInferUrgentSurgicalUnresponsiveWithAirwayIntervention() {
        var st = emptyState()
        st.march.consciousness = "unresponsive"
        st.march.airwayIntervention = "NPA inserted"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testInferUrgentSurgicalPneumothoraxWithChestSeal() {
        var st = emptyState()
        st.march.respirationStatus = "possible pneumothorax"
        st.march.respirationIntervention = "chest seal"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testInferUrgentSurgicalBilateralHemorrhage() {
        // Mirror scenario_2 PATIENT_1: bilateral TQs + NPA + chest seal
        // -> Urgent Surgical
        var st = emptyState()
        st.march.hemorrhageLocation = "bilateral lower extremities"
        st.march.hemorrhageIntervention = "tourniquet applied"
        st.march.airwayIntervention = "NPA inserted"
        st.march.respirationIntervention = "chest seal"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testInferUrgentSurgicalSurgicalAirway() {
        var st = emptyState()
        st.march.airwayIntervention = "surgical cricothyroidotomy"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }

    func testInferUrgentTourniquetPlusTachycardia() {
        // Mirror scenario_1: HR 110 + BP 90/60 + tourniquet → Urgent
        var st = emptyState()
        st.vitals = Vitals(hr: 150, bp: BloodPressure(systolic: 70, diastolic: 40))
        st.march.hemorrhageIntervention = "tourniquet applied"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentTachycardiaAlone() {
        var st = emptyState()
        st.vitals = Vitals(hr: 138)
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentHypotensionAlone() {
        var st = emptyState()
        st.vitals = Vitals(bp: BloodPressure(systolic: 80, diastolic: 50))
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentHypoxia() {
        var st = emptyState()
        st.vitals = Vitals(spo2: 88)
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentRespiratoryDistressLow() {
        var st = emptyState()
        st.vitals = Vitals(rr: 8)
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentRespiratoryDistressHigh() {
        var st = emptyState()
        st.vitals = Vitals(rr: 30)
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentVoiceConsciousness() {
        var st = emptyState()
        st.march.consciousness = "Voice"
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferUrgentFemurFracture() {
        // Mirror scenario_4 inference path.
        var st = emptyState()
        st.injuries = ["Right femur fracture"]
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    func testInferPriorityModerateTachycardia() {
        var st = emptyState()
        st.vitals = Vitals(hr: 95)
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .priority)
    }

    func testInferPriorityHemorrhageControlled() {
        var st = emptyState()
        st.march.hemorrhageIdentified = true
        st.march.hemorrhageEffective = true
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .priority)
    }

    func testInferRoutineAlertStableNoIntervention() {
        var st = emptyState()
        st.march.consciousness = "Alert"
        st.vitals = Vitals(hr: 80, bp: BloodPressure(systolic: 120, diastolic: 80))
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .routine)
    }

    func testInferReturnsNilWhenNothingKnown() {
        let s = extractor.apply(
            emptyState(), context: ctx("Continuing assessment."))
        XCTAssertNil(s.classification,
                     "Empty state with no findings should leave classification nil")
    }

    // MARK: - Explicit overwrites previously-inferred

    func testExplicitOverwritesInferred() {
        var st = emptyState()
        st.classification = .priority  // pretend a previous pass inferred Priority
        let s = extractor.apply(
            st,
            context: ctx("This is an urgent casualty."))
        XCTAssertEqual(s.classification, .urgent,
                       "Explicit per-sentence classification must overwrite a stale inference")
    }

    // MARK: - Inference does not overwrite an existing classification

    func testInferenceDoesNotOverwriteExistingClassification() {
        // Mirror Python finalize_classifications guard: if classification is
        // already set, leave it alone (state.py:1100–1102).
        var st = emptyState()
        st.classification = .urgent
        st.vitals = Vitals(hr: 70, bp: BloodPressure(systolic: 120, diastolic: 80))
        st.march.consciousness = "Alert"
        // Sentence has no explicit classification language. Inference would
        // say Routine — but classification is already Urgent, so no change.
        let s = extractor.apply(st, context: ctx("Continuing assessment."))
        XCTAssertEqual(s.classification, .urgent)
    }

    // MARK: - Pattern ordering — urgent surgical wins over urgent

    func testUrgentSurgicalBeatsUrgent() {
        // The compound phrase "urgent surgical" should classify as Urgent
        // Surgical, not Urgent (state.py:451–453 ordering).
        let s = extractor.apply(
            emptyState(),
            context: ctx("Patient is urgent surgical, prep the OR."))
        XCTAssertEqual(s.classification, .urgentSurgical)
    }
}
