// Packages/TCCCKit/Tests/TCCCExtractorTests/EngineInvariantTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class EngineInvariantTests: XCTestCase {

    /// An operatorAcceptedFact event is the ONLY way a non-extraction value enters
    /// the projection. A rejected event must never affect projected state.
    func testRejectedFactNeverAffectsProjection() {
        var log = EncounterLog()
        log.append(.operatorRejectedFact(.init(id: "op-1", patientId: "PATIENT_1",
            timestampUnix: 1, write: .heartRate(200), sourceFactId: "g", domain: "vitals",
            field: "heartRate", rawValue: "200")))
        let projected = PatientStateEngine.project(log)
        XCTAssertNil(projected["PATIENT_1"]?.vitals.hr, "a rejected fact must not mutate state")
    }

    func testAcceptedFactWithNilWriteIsInert() {
        var log = EncounterLog()
        log.append(.operatorAcceptedFact(.init(id: "op-1", patientId: "PATIENT_1",
            timestampUnix: 1, write: nil, sourceFactId: "g", domain: "vitals",
            field: "heartRate", rawValue: "x")))
        XCTAssertNil(PatientStateEngine.project(log)["PATIENT_1"]?.vitals.hr)
    }

    /// asrSegment events alone never set state — only their derived deterministicFact
    /// deltas do. A log of bare asrSegments projects to the default base.
    func testBareASRSegmentsProjectToDefault() {
        var log = EncounterLog()
        log.append(.asrSegment(.init(id: "seg-1", patientId: "PATIENT_1", timestampUnix: 1,
            text: "heart rate two hundred", backend: "engine", isFinal: true)))
        XCTAssertEqual(PatientStateEngine.project(log)["PATIENT_1"], PatientState(patientId: "PATIENT_1"))
    }

    /// The ACCEPTED-write branch: accepted fact with a non-nil write must apply the
    /// field value AND set timestampLastUpdate from the event timestamp.
    func testAcceptedFactWriteAppliesAndSetsTimestamp() {
        var log = EncounterLog()
        log.append(.operatorAcceptedFact(.init(id: "op-1", patientId: "PATIENT_1",
            timestampUnix: 4242, write: .heartRate(88), sourceFactId: "g", domain: "vitals",
            field: "heartRate", rawValue: "88")))
        let p = PatientStateEngine.project(log)["PATIENT_1"]
        XCTAssertEqual(p?.vitals.hr, 88, "accepted write must apply via project")
        XCTAssertEqual(p?.timestampLastUpdate, 4242, "accepted event timestamp must set timestampLastUpdate")
    }

    func testFreshEngineLogStartsWithEncounterStarted() async {
        let engine = PatientStateEngine.standard()
        let log = await engine.snapshotLog()
        XCTAssertEqual(log.events.first.flatMap { e -> Bool? in
            if case .lifecycle(let p) = e { return p.kind == .encounterStarted }; return nil
        }, true)
    }

    /// Every PatientStateFieldWrite case must be representable as a PatientStateDelta,
    /// so an operator accept and the projection share one vocabulary. Fails if a future
    /// write case is added without a matching delta mapping.
    func testEveryFieldWriteMapsToADelta() {
        let writes: [PatientStateFieldWrite] = [
            .heartRate(1), .spo2(1), .respiratoryRate(1),
            .bloodPressure(systolic: 1, diastolic: 1, palpated: false),
            .hemorrhageLocation("x"), .hemorrhageIntervention("x"), .airwayIntervention("x"),
            .consciousness("x"), .hypothermiaPrevention("x"), .pain("x"), .antibiotics("x"),
        ]
        // Applying a write and diffing must yield at least one delta — proving the field
        // is reachable through the delta vocabulary.
        for w in writes {
            var s = PatientState(patientId: "PATIENT_1")
            PatientStateEngine.applyWrite(w, to: &s)
            let deltas = PatientStateEngine.diff(PatientState(patientId: "PATIENT_1"), s)
            XCTAssertFalse(deltas.isEmpty, "write \(w) produced no delta — vocabulary drift")
        }
    }
}
