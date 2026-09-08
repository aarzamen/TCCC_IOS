// VitalsNarrationTests
//
// Regression coverage for stated-vitals extraction from ordinary medic
// narration, driven by the exact-text reference control failures observed
// on device (2026-09-08 sprint):
//
//   - "Heart rate is down to 110."  → HR stayed at the earlier 120
//   - "Respirations are fast, about 22 per minute, slightly labored." → RR missing
//   - "Oxygen saturation is 97 percent."  → SpO2 missing
//
// plus the field-local negation contract: a negation marker anywhere in the
// sentence must only suppress the vital it actually scopes over, never
// unrelated positives elsewhere in the same sentence. Numeric goal /
// planned / conditional phrases ("target heart rate 100") are not
// observations and must not be recorded.
//
// RR uses the latest affirmed reading, consistent with the other vitals.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class VitalsNarrationTests: XCTestCase {

    private let extractor = VitalsExtractor()

    // MARK: - Helpers

    private func ctx(
        _ sentence: String,
        isNegated: Bool = false,
        patient: String = "PATIENT_1"
    ) -> ExtractionContext {
        return ExtractionContext(
            originalText: sentence,
            normalizedText: sentence,
            sentence: sentence,
            timestamp: Date(timeIntervalSince1970: 0),
            currentPatientID: patient,
            isNegated: isNegated
        )
    }

    private func emptyState() -> PatientState {
        return PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Reference-control failures (device synthetic ASR phrasing)

    func testHRUpdatesOnDownToPhrase() {
        var seed = emptyState()
        seed.vitals = Vitals(hr: 120)
        let s = extractor.apply(
            seed, context: ctx("Heart rate is down to 110."))
        XCTAssertEqual(s.vitals.hr, 110,
                       "'down to' narration must update the earlier HR")
    }

    func testRRFromRespirationsNarration() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Respirations are fast, about 22 per minute, slightly labored."))
        XCTAssertEqual(s.vitals.rr, 22)
    }

    func testSpO2FromOxygenSaturationPercent() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("Oxygen saturation is 97 percent."))
        XCTAssertEqual(s.vitals.spo2, 97)
    }

    // MARK: - Field-local negation: unrelated positives survive

    func testUnrelatedLeadingNegationDoesNotSwallowHR() {
        // Engine tags the sentence negated because of "No allergies";
        // the HR clause is affirmative and must still record.
        let s = extractor.apply(
            emptyState(),
            context: ctx("No allergies, heart rate is 110", isNegated: true))
        XCTAssertEqual(s.vitals.hr, 110)
    }

    func testMultiWordNegationPrefixDoesNotSwallowLaterPulse() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no evidence of bleeding, pulse 105", isNegated: true))
        XCTAssertEqual(s.vitals.hr, 105)
    }

    func testNoMeasurablePulseRecordsNothing() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("No measurable pulse", isNegated: true))
        XCTAssertNil(s.vitals.hr)
    }

    func testNegatedNumericHRNotRecorded() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("HR is not 120", isNegated: true))
        XCTAssertNil(s.vitals.hr)
    }

    func testNegatedHRDoesNotBlockBPInSameSentence() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no heart rate 120, BP 90/60", isNegated: true))
        XCTAssertNil(s.vitals.hr, "Negated HR must stay unrecorded")
        XCTAssertEqual(s.vitals.bp?.systolic, 90)
        XCTAssertEqual(s.vitals.bp?.diastolic, 60)
    }

    func testNoPulseCommaRespirationsRecordsRROnly() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("No pulse, respirations 22", isNegated: true))
        XCTAssertNil(s.vitals.hr)
        XCTAssertEqual(s.vitals.rr, 22)
    }

    func testOrConjunctionCarriesNegationAcrossBothVitals() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("no HR 120 or RR 22", isNegated: true))
        XCTAssertNil(s.vitals.hr)
        XCTAssertNil(s.vitals.rr)
    }

    // MARK: - Goal / planned / conditional numbers are not observations

    func testTargetHeartRateNotRecorded() {
        let s = extractor.apply(
            emptyState(), context: ctx("target heart rate 100"))
        XCTAssertNil(s.vitals.hr)
    }

    func testConditionalHRNotRecorded() {
        let s = extractor.apply(
            emptyState(), context: ctx("if HR 100, start fluids"))
        XCTAssertNil(s.vitals.hr)
    }

    func testAimForOxygenSaturationNotRecorded() {
        let s = extractor.apply(
            emptyState(), context: ctx("aim for oxygen saturation 97"))
        XCTAssertNil(s.vitals.spo2)
    }

    // MARK: - Latest affirmed measurement wins within one sentence

    func testLatestAffirmedHRWinsWithinSentence() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("First pulse 120, recheck heart rate is 110"))
        XCTAssertEqual(s.vitals.hr, 110,
                       "Later affirmed HR in the same sentence should win")
    }

    func testTrailingNegatedRepeatDoesNotDisplaceAffirmedHR() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("HR 110 but HR not 130", isNegated: true))
        XCTAssertEqual(s.vitals.hr, 110)
    }

    // MARK: - RR reassessment semantics

    func testRRUpdatesOnExplicitReassessment() {
        var seed = emptyState()
        seed.vitals = Vitals(rr: 18)
        let s = extractor.apply(
            seed,
            context: ctx("Reassessment: respiratory rate is now 24"))
        XCTAssertEqual(s.vitals.rr, 24,
                       "Explicit reassessment must update the stale RR")
    }

    func testRRUpdatesOnDownToTrend() {
        var seed = emptyState()
        seed.vitals = Vitals(rr: 28)
        let s = extractor.apply(
            seed, context: ctx("respirations down to 18"))
        XCTAssertEqual(s.vitals.rr, 18)
    }

    func testRRPlainRestatementUpdatesValue() {
        // A later numeric observation needs no special reassessment phrase.
        var seed = emptyState()
        seed.vitals = Vitals(rr: 18)
        let s = extractor.apply(seed, context: ctx("RR 30"))
        XCTAssertEqual(s.vitals.rr, 30)
    }

    // MARK: - Mixed narration line with an unrelated negation

    func testFullNarrationLineWithLeadingNegation() {
        let s = extractor.apply(
            emptyState(),
            context: ctx(
                "No bleeding noted, vitals: heart rate 88, " +
                "blood pressure 118 over 76, oxygen saturation is 99 percent, " +
                "respirations about 16.",
                isNegated: true))
        XCTAssertEqual(s.vitals.hr, 88)
        XCTAssertEqual(s.vitals.bp?.systolic, 118)
        XCTAssertEqual(s.vitals.bp?.diastolic, 76)
        XCTAssertEqual(s.vitals.spo2, 99)
        XCTAssertEqual(s.vitals.rr, 16)
    }

    // MARK: - Legacy behaviours preserved under narration phrasing

    func testBPPalpatedStillWorksWithNarrationGap() {
        let s = extractor.apply(
            emptyState(),
            context: ctx("blood pressure is down to 80 over 40 palpated"))
        XCTAssertEqual(s.vitals.bp?.systolic, 80)
        XCTAssertEqual(s.vitals.bp?.diastolic, 40)
        XCTAssertTrue(s.vitals.bp?.palpated ?? false)
    }

    func testOutOfRangeNarrationValuesStillDropped() {
        let s = extractor.apply(
            emptyState(), context: ctx("Heart rate is down to 900."))
        XCTAssertNil(s.vitals.hr, "HR 900 is out of physiological range")
    }

    func testOutOfRangeNarrationDoesNotDestroyPriorValue() {
        var seed = emptyState()
        seed.vitals = Vitals(spo2: 95)
        let s = extractor.apply(
            seed, context: ctx("oxygen saturation is 150 percent"))
        XCTAssertEqual(s.vitals.spo2, 95,
                       "Junk out-of-range reading must not wipe a prior valid one")
    }

    func testAbbreviationInsideWordDoesNotMatch() {
        let s = extractor.apply(
            emptyState(), context: ctx("shrapnel 3 fragments in the thigh"))
        XCTAssertNil(s.vitals.hr, "'hr' inside 'shrapnel' must not read as heart rate")
    }
}
