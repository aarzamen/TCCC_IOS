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
}
