// Packages/TCCCKit/Tests/TCCCExtractorTests/PatientStateDiffTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class PatientStateDiffTests: XCTestCase {

    /// The central correctness obligation: replaying the diff reconstructs `after`.
    private func assertInverse(_ before: PatientState, _ after: PatientState,
                               file: StaticString = #filePath, line: UInt = #line) {
        let deltas = PatientStateEngine.diff(before, after)
        var rebuilt = before
        for d in deltas { PatientStateEngine.applyDelta(d, to: &rebuilt) }
        XCTAssertEqual(rebuilt, after, "diff+apply did not reconstruct after", file: file, line: line)
    }

    func testInverseHoldsForEveryScalarFieldFamily() {
        let base = PatientState(patientId: "PATIENT_1")
        var a = base; a.mechanismOfInjury = "GSW"; assertInverse(base, a)
        var b = base; b.marchPhase = .circulation; assertInverse(base, b)
        var c = base; c.classification = .urgentSurgical; assertInverse(base, c)
        var d = base; d.timestampFirstMention = 12; d.timestampLastUpdate = 34; assertInverse(base, d)
        var e = base; e.vitals.hr = 110; e.vitals.spo2 = 96; e.vitals.rr = 18
        e.vitals.gcs = 14; e.vitals.temperatureCelsius = 36.5; e.vitals.capillaryRefillSeconds = 2.0
        e.vitals.bp = BloodPressure(systolic: 90, diastolic: 60, palpated: true); assertInverse(base, e)
        var f = base
        f.march.hemorrhageIdentified = true; f.march.hemorrhageAssessed = true
        f.march.hemorrhageLocation = "right thigh"; f.march.hemorrhageIntervention = "tourniquet"
        f.march.hemorrhageEffective = true; f.march.airwayStatus = "patent"
        f.march.airwayIntervention = "NPA"; f.march.respirationStatus = "labored"
        f.march.respirationIntervention = "chest seal"; f.march.breathSounds = "bilateral equal"
        f.march.pulseStatus = "weak radial"; f.march.skinSigns = "cool clammy"
        f.march.circulationIntervention = "IV access"; f.march.consciousness = "Alert"
        f.march.pupilResponse = "PERRL"; f.march.hypothermiaPrevention = "wrap"; assertInverse(base, f)
        var g = base; g.paws.pain = "ketamine"; g.paws.antibiotics = "moxifloxacin"
        g.paws.wounds = "wound care"; g.paws.splinting = "SAM splint"; assertInverse(base, g)
    }

    func testInverseHoldsForCollectionAppend() {
        let base = PatientState(patientId: "PATIENT_1")
        var a = base
        a.injuries = ["femur fracture", "laceration"]
        a.interventions = [
            Intervention(timestamp: Date(timeIntervalSince1970: 1), kind: .tourniquet, description: "TQ"),
            Intervention(timestamp: Date(timeIntervalSince1970: 2), kind: .npa, description: "NPA"),
        ]
        // append-only growth → expect append deltas, and inverse holds (UUIDs preserved)
        let deltas = PatientStateEngine.diff(base, a)
        XCTAssertTrue(deltas.contains { if case .appendInjury = $0 { return true }; return false })
        XCTAssertTrue(deltas.contains { if case .appendIntervention = $0 { return true }; return false })
        assertInverse(base, a)
    }

    func testInverseHoldsForNonPrefixCollectionChangeViaSetFallback() {
        var before = PatientState(patientId: "PATIENT_1")
        before.injuries = ["x", "y"]
        var after = before
        after.injuries = ["z"]               // not a prefix-extension of before → set fallback
        let deltas = PatientStateEngine.diff(before, after)
        XCTAssertTrue(deltas.contains { if case .setInjuries = $0 { return true }; return false })
        assertInverse(before, after)
    }

    func testInverseHoldsClearingOptionalToNil() {
        var before = PatientState(patientId: "PATIENT_1")
        before.mechanismOfInjury = "GSW"; before.vitals.hr = 110
        var after = before
        after.mechanismOfInjury = nil; after.vitals.hr = nil
        assertInverse(before, after)
    }

    func testEmptyDiffWhenUnchanged() {
        let s = PatientState(patientId: "PATIENT_1")
        XCTAssertTrue(PatientStateEngine.diff(s, s).isEmpty)
    }
}
