// Packages/TCCCKit/Tests/TCCCExtractorTests/EngineRestoreTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class EngineRestoreTests: XCTestCase {
    func testRestoreReproducesSnapshotAndResumesIds() async throws {
        let source = PatientStateEngine.standard()
        await source.processTranscript("GSW right thigh. Heart rate one ten.")
        let savedLog = await source.snapshotLog()
        let savedSnapshot = await source.snapshot()

        let restored = PatientStateEngine.standard()
        await restored.restore(savedLog)
        let restoredSnapshot = await restored.snapshot()
        XCTAssertEqual(restoredSnapshot, savedSnapshot, "restore must reproduce projected state exactly")

        // A subsequent mutation must not reuse an id already in the restored log.
        await restored.processTranscript("Blood pressure ninety over sixty.")
        let ids = await restored.snapshotLog().events.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no id collisions after restore")
    }

    func testRecordLifecycleAppendsInertMarker() async throws {
        let engine = PatientStateEngine.standard()
        let before = await engine.snapshot()
        await engine.recordLifecycle(.encounterEnded)
        let after = await engine.snapshot()
        XCTAssertEqual(after, before, "a lifecycle marker must not change state")
        let events = await engine.snapshotLog().events
        XCTAssertTrue(events.contains {
            if case .lifecycle(let p) = $0, p.kind == .encounterEnded { return true }; return false
        })
    }
}
