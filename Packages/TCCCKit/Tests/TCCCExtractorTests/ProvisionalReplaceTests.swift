import XCTest
@testable import TCCCExtractor
@testable import TCCCDomain

final class ProvisionalReplaceTests: XCTestCase {
    func testTruncateDropsTailToCount() {
        var log = EncounterLog()
        let seg = { (i: Int) in EncounterEvent.asrSegment(.init(
            id: "s\(i)", patientId: "PATIENT_1", timestampUnix: 0, text: "t\(i)",
            backend: "test", isFinal: true)) }
        log.append(seg(0)); log.append(seg(1)); log.append(seg(2))
        log.truncate(toCount: 1)
        XCTAssertEqual(log.events.map(\.id), ["s0"])
    }

    func testTruncateNoopWhenCountAtOrAboveLength() {
        var log = EncounterLog()
        log.append(.asrSegment(.init(id: "s0", patientId: "P", timestampUnix: 0,
            text: "t", backend: "test", isFinal: true)))
        log.truncate(toCount: 5)
        XCTAssertEqual(log.events.count, 1)
    }
}

extension ProvisionalReplaceTests {
    func testRefinedWordsWinMatchesFreshEngine() async {
        let revised = PatientStateEngine.standard()
        await revised.commitProvisional("TQ applied high end to the left thigh")
        await revised.reviseProvisional("TQ applied high and tight to the left thigh")
        await revised.settleProvisional()

        let fresh = PatientStateEngine.standard()
        await fresh.processTranscript("TQ applied high and tight to the left thigh")

        let a = await revised.snapshot()
        let b = await fresh.snapshot()
        // Compare clinical (deterministic) fields. Intervention.id is a random UUID
        // minted per-creation, so two independently-running engines are guaranteed to
        // produce different UUIDs and different wall-clock timestamps — full struct ==
        // cannot hold across independent engines. The assertion below verifies that the
        // *refined* text wins (not the original provisional text) by checking the
        // deterministic MARCH and PAWS fields that the extractors set.
        XCTAssertEqual(a["PATIENT_1"]?.march, b["PATIENT_1"]?.march)
        XCTAssertEqual(a["PATIENT_1"]?.vitals, b["PATIENT_1"]?.vitals)
        XCTAssertEqual(a["PATIENT_1"]?.paws, b["PATIENT_1"]?.paws)
        XCTAssertEqual(a["PATIENT_1"]?.marchPhase, b["PATIENT_1"]?.marchPhase)
        XCTAssertEqual(a["PATIENT_1"]?.classification, b["PATIENT_1"]?.classification)
        XCTAssertEqual(a["PATIENT_1"]?.injuries, b["PATIENT_1"]?.injuries)
        XCTAssertEqual(a["PATIENT_1"]?.mechanismOfInjury, b["PATIENT_1"]?.mechanismOfInjury)
        // Verify the refined text's intervention description won (not the provisional text)
        XCTAssertEqual(
            a["PATIENT_1"]?.interventions.map(\.description),
            b["PATIENT_1"]?.interventions.map(\.description)
        )
    }

    func testReviseKeepsSnapshotEqualToProjection() async {
        let e = PatientStateEngine.standard()
        await e.commitProvisional("bp is 80 over 50")
        await e.reviseProvisional("bp is 90 over 60")
        await e.settleProvisional()
        let snap = await e.snapshot()
        let log = await e.snapshotLog()
        let proj = PatientStateEngine.project(log)   // nonisolated static, synchronous
        XCTAssertEqual(snap, proj)
    }

    func testRetiredAsrSegmentRetainedAndIgnoredByProjection() async {
        let e = PatientStateEngine.standard()
        await e.commitProvisional("spo2 is ninety")
        await e.reviseProvisional("spo2 is ninety four")
        await e.settleProvisional()
        let log = await e.snapshotLog()
        let retired = log.events.filter {
            if case .asrSegment(let p) = $0 { return p.id.hasSuffix("-retired") }
            return false
        }
        XCTAssertEqual(retired.count, 1)
        // projection identical with/without the retired segment present
        let withRetired = PatientStateEngine.project(log)
        var stripped = EncounterLog()
        for ev in log.events where !(ev.id.hasSuffix("-retired")) { stripped.append(ev) }
        let withoutRetired = PatientStateEngine.project(stripped)
        XCTAssertEqual(withRetired, withoutRetired)
    }

    func testCommitThenReviseThenNextCommitStaysEquivalent() async {
        let e = PatientStateEngine.standard()
        await e.commitProvisional("tourniquet on left arm")
        await e.reviseProvisional("tourniquet on left leg")
        await e.settleProvisional()
        await e.commitProvisional("bp 100 over 70")
        await e.settleProvisional()
        let snap = await e.snapshot()
        let log = await e.snapshotLog()
        let proj = PatientStateEngine.project(log)
        XCTAssertEqual(snap, proj)
    }

    /// Regression: when a foreign event (e.g. a lifecycle marker) is appended AFTER
    /// `commitProvisional` but BEFORE `reviseProvisional`, the tail-guard must detect
    /// the interleave and take the loss-safe fallback — append the refined text as a
    /// fresh chunk — rather than truncating and silently discarding the foreign event.
    func testReviseFallsBackToFreshAppendWhenForeignEventInterleaved() async {
        let e = PatientStateEngine.standard()
        await e.commitProvisional("tourniquet on left arm")

        // Interleave a foreign event after the provisional chunk.
        await e.recordLifecycle(.encounterEnded)

        let countBefore = await e.snapshotLog().events.count
        await e.reviseProvisional("tourniquet on left leg")

        let log = await e.snapshotLog()

        // 1. The foreign lifecycle event must NOT have been discarded.
        let hasEncounterEnded = log.events.contains {
            if case .lifecycle(let p) = $0 { return p.kind == .encounterEnded }
            return false
        }
        XCTAssertTrue(hasEncounterEnded, "foreign lifecycle event must survive the fallback path")

        // 2. The log must have grown (refined text appended as a fresh chunk), not shrunk.
        XCTAssertGreaterThan(log.events.count, countBefore,
            "fallback must append refined text as a new chunk, not truncate")

        // 3. The equivalence invariant must still hold after the fallback.
        let snap = await e.snapshot()
        let proj = PatientStateEngine.project(log)
        XCTAssertEqual(snap, proj,
            "snapshot() must equal project(log) after the loss-safe fallback")
    }
}
