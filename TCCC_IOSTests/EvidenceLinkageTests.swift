// TCCC_IOSTests/EvidenceLinkageTests.swift
import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class EvidenceLinkageTests: XCTestCase {

    func testDeterministicFactsCarryRealSegmentEvidence() async throws {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("Heart rate one ten.")
        let log = await engine.snapshotLog()
        let facts = PatientStateEngine.deterministicFacts(from: log)
        let hr = try XCTUnwrap(facts.first { $0.domain == "vitals" && $0.field == "heartRate" })
        XCTAssertEqual(hr.value, "110")
        XCTAssertFalse(hr.evidenceIds.isEmpty, "evidence must trace to an asrSegment id")
        XCTAssertTrue(hr.evidenceIds.allSatisfy { $0.hasPrefix("seg-") })
    }

    func testProjectorEmitsNonEmptyEvidenceFromLog() async throws {
        let state = AppState()
        await state.engine.processTranscript("BP ninety over sixty.")
        let facts = await state.deterministicFactsForPacket()   // new app accessor over the log
        XCTAssertTrue(facts.contains { $0.field == "bloodPressure" && !$0.evidenceIds.isEmpty })
    }
}
