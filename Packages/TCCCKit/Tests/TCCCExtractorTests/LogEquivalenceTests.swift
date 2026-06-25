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

    func testAfterFlipSnapshotIsTheProjection() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript(try loadScenario("scenario_1_gsw_thigh"))
        let snap = await engine.snapshot()
        let projected = PatientStateEngine.project(await engine.snapshotLog())
        XCTAssertEqual(snap, projected)            // snapshot IS the fold, not a parallel imperative copy
        // And a known field still lands (guards against an all-empty projection passing trivially):
        XCTAssertEqual(snap["PATIENT_1"]?.vitals.hr, 110)
    }
}
