// Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

/// The de-risker: the fold of the log a transcript produced must equal the
/// imperative result, field-by-field (full ==), over the real scenario fixtures.
final class LogEquivalenceTests: XCTestCase {

    private func loadScenario(_ name: String) throws -> String {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "scenarios"),
            "Scenario fixture \(name).txt not found")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertFoldEqualsImperative(_ scenario: String) async throws {
        let engine = PatientStateEngine.standard()
        let text = try loadScenario(scenario)
        await engine.processTranscript(text)
        let imperative = await engine.snapshot()
        let log = await engine.snapshotLog()
        let projected = PatientStateEngine.project(log)
        XCTAssertEqual(projected, imperative, "fold != imperative for \(scenario)")
    }

    func testScenario1FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_1_gsw_thigh") }
    func testScenario2FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_2_blast_multi") }
    func testScenario3FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_3_mre_laceration") }
    func testScenario4FoldEqualsImperative() async throws { try await assertFoldEqualsImperative("scenario_4_femur_fracture") }

    func testMultiChunkFoldEqualsImperative() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW upper right thigh.")
        await engine.processTranscript("Heart rate one ten.")
        await engine.processTranscript("Blood pressure ninety over sixty.")
        let imperative = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(projected, imperative)
    }

    func testProjectionIsIdempotent() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(try loadScenario("scenario_2_blast_multi"))
        let log = await engine.snapshotLog()
        XCTAssertEqual(PatientStateEngine.project(log), PatientStateEngine.project(log))
    }

    func testLogAccumulatesASRAndFactEvents() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Heart rate one ten.")
        let log = await engine.snapshotLog()
        XCTAssertTrue(log.events.contains { if case .asrSegment = $0 { return true }; return false })
        XCTAssertTrue(log.events.contains {
            if case .deterministicFact(let p) = $0, case .vitalsHR(110) = p.delta { return true }; return false
        })
    }

    func testProjectionReconstructsSwitchedPatientKeySet() async throws {
        // A patient switch must reconstruct the second patient's row in the projection,
        // so project(log)'s key set matches the imperative dict. Guards the key-set
        // invariant that sub-cycle B's replay-on-launch depends on.
        let engine = PatientStateEngine.standard()
        let text = try loadScenario("scenario_2_blast_multi")   // known to trigger a PATIENT_2 switch
        await engine.processTranscript(text)
        let imperative = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertTrue(imperative.keys.contains("PATIENT_2"),
                      "precondition: the fixture must actually switch to PATIENT_2 (else the test is vacuous)")
        XCTAssertEqual(Set(projected.keys), Set(imperative.keys),
                       "project(log) must reconstruct the same patient key set as the imperative dict")
        XCTAssertEqual(projected, imperative)
    }

    func testFactlessPatientSwitchReconstructsRowInProjection() async throws {
        // A patient created with NO clinical facts (only a switch) must still appear
        // in project(log) — the key-set invariant replay depends on, made structural.
        let engine = PatientStateEngine.standard()
        // PatientSwitcher recognizes "patient two"; this switch sets timestamps too,
        // but the GUARANTEE must come from the lifecycle event, not the timestamp coupling.
        await engine.processTranscript("Switching to patient two.")
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(Set(projected.keys), Set(snap.keys))
        // The lifecycle event for the new patient must be present in the log.
        let log = await engine.snapshotLog()
        XCTAssertTrue(log.events.contains {
            if case .lifecycle(let p) = $0, p.kind == .encounterStarted, p.patientId != "PATIENT_1" { return true }
            return false
        }, "a new patient must emit an encounterStarted lifecycle event")
    }

    func testAfterFlipSnapshotIsTheProjection() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(try loadScenario("scenario_1_gsw_thigh"))
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(snap, projected)            // snapshot IS the fold, not a parallel imperative copy
        // And a known field still lands (guards against an all-empty projection passing trivially):
        XCTAssertEqual(snap["PATIENT_1"]?.vitals.hr, 110)
    }

    func testIncrementalProjectionNeverDivergesAcrossTranscriptAndAccepts() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW right thigh. Heart rate one ten.")
        await engine.recordOperatorAcceptedFact(
            write: .spo2(94), factId: "g1", domain: "vitals", field: "spo2",
            rawValue: "94", to: "PATIENT_1")
        await engine.processTranscript("Blood pressure ninety over sixty. Tourniquet applied.")
        await engine.recordOperatorAcceptedFact(
            write: .pain("ketamine"), factId: "g2", domain: "paws", field: "pain",
            rawValue: "ketamine", to: "PATIENT_1")
        await engine.processTranscript("Patient is alert.")

        // The incrementally-maintained snapshot must equal a fresh full re-fold of the log.
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(snap, projected,
                      "incremental materialized view must never diverge from project(log)")
        // …and the accepted writes actually landed through the incremental path:
        XCTAssertEqual(snap["PATIENT_1"]?.vitals.spo2, 94)
        XCTAssertEqual(snap["PATIENT_1"]?.paws.pain, "ketamine")
    }

    func testNewEventsSinceReturnsSuffixOrEmpty() async throws {
        let engine = PatientStateEngine.standard()
        // A multi-sentence chunk so the log has comfortably more than 4 events,
        // giving a genuine interior cursor to exercise.
        await engine.processTranscript("GSW right thigh. Heart rate one ten. Blood pressure ninety over sixty.")
        let allEvents = await engine.snapshotLog().events
        let total = allEvents.count
        XCTAssertGreaterThan(total, 4)                                       // seed + asr + several facts

        // By value, not just count: a same-length-but-wrong slice (prefix, reversed)
        // must fail. persistNewEvents writes exactly this slice to the encrypted JSONL.
        let wholeLog = await engine.newEvents(since: 0)
        XCTAssertEqual(wholeLog.map(\.id), allEvents.map(\.id))              // whole log, in order
        let tail = await engine.newEvents(since: total - 1)
        XCTAssertEqual(tail.map(\.id), [allEvents.last!.id])                 // exactly the last event
        let interior = await engine.newEvents(since: 2)
        XCTAssertEqual(interior.map(\.id), Array(allEvents[2...]).map(\.id)) // interior cursor == events[2...]
        let caughtUp = await engine.newEvents(since: total)
        XCTAssertTrue(caughtUp.isEmpty)                                      // caught up
        let outOfRange = await engine.newEvents(since: total + 5)
        XCTAssertTrue(outOfRange.isEmpty)                                    // out-of-range guarded
    }

    func testRestoreThenMutateNeverDivergesFromProjection() async throws {
        // Production crash-recovery hot path (continuous persistence): restore a
        // persisted log via the full fold, then keep capturing along the incremental
        // path. The materialized view must stay == project(log) after restore+mutate —
        // the equivalence the incremental change relies on, on the path that doesn't
        // build `patients` from scratch.
        let source = PatientStateEngine.standard()
        await source.processTranscript("GSW right thigh. Heart rate one ten.")
        await source.recordOperatorAcceptedFact(
            write: .spo2(94), factId: "g1", domain: "vitals", field: "spo2",
            rawValue: "94", to: "PATIENT_1")
        let savedLog = await source.snapshotLog()

        let restored = PatientStateEngine.standard()
        await restored.restore(savedLog)
        await restored.processTranscript("Blood pressure ninety over sixty. Tourniquet applied.")
        await restored.recordOperatorAcceptedFact(
            write: .pain("ketamine"), factId: "g2", domain: "paws", field: "pain",
            rawValue: "ketamine", to: "PATIENT_1")

        let snap = await restored.snapshot()
        let projected = PatientStateEngine.project(await restored.snapshotLog())
        XCTAssertEqual(snap, projected,
                      "restore-then-mutate: materialized view must equal a fresh re-fold")
        XCTAssertEqual(snap["PATIENT_1"]?.vitals.spo2, 94)        // survived restore
        XCTAssertEqual(snap["PATIENT_1"]?.paws.pain, "ketamine")  // applied post-restore
    }

    func testAcceptToBrandNewPatientNeverDivergesFromProjection() async throws {
        // recordOperatorAcceptedFact to a not-yet-created id: the engine emits a
        // lifecycle(.encounterStarted) + the accept event; project() must ensure() the
        // row and applyWrite to the same result. Both accept-path tests previously
        // targeted only the pre-existing current patient (PATIENT_1).
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW right thigh.")        // currentPatientID == PATIENT_1
        await engine.recordOperatorAcceptedFact(
            write: .heartRate(120), factId: "g1", domain: "vitals", field: "heartRate",
            rawValue: "120", to: "PATIENT_2")                     // creates PATIENT_2 via accept
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertTrue(snap.keys.contains("PATIENT_2"), "accept must create the new patient row")
        XCTAssertEqual(Set(snap.keys), Set(projected.keys))
        XCTAssertEqual(snap, projected, "accept-to-new-patient must equal project(log)")
        XCTAssertEqual(snap["PATIENT_2"]?.vitals.hr, 120)
    }

    func testSwitchThenAcceptToNonCurrentPatientNeverDivergesFromProjection() async throws {
        // Multi-casualty: a transcript switch moves currentPatientID to PATIENT_2, then
        // an accept targets PATIENT_1 (non-current — accepts key off the explicit
        // patientId argument, not currentPatientID). Equivalence must still hold.
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("GSW right thigh.")
        await engine.processTranscript("Switching to patient two. Heart rate one twenty.")
        let snap0 = await engine.snapshot()
        XCTAssertTrue(snap0.keys.contains("PATIENT_2"),
                      "precondition: the switch must create PATIENT_2 (else the test is vacuous)")
        await engine.recordOperatorAcceptedFact(
            write: .spo2(91), factId: "g1", domain: "vitals", field: "spo2",
            rawValue: "91", to: "PATIENT_1")                     // accept to the non-current patient
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(Set(snap.keys), Set(projected.keys))
        XCTAssertEqual(snap, projected,
                      "switch-then-accept-to-non-current must equal project(log)")
        XCTAssertEqual(snap["PATIENT_1"]?.vitals.spo2, 91)
    }
}
