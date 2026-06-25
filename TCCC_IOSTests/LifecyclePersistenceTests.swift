// TCCC_IOSTests/LifecyclePersistenceTests.swift
import XCTest
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class LifecyclePersistenceTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("lp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    // B4 configures the store MANUALLY (load() doesn't exist until B5).
    func testTranscriptEventsArePersistedContinuously() async throws {
        let state = AppState()
        state.documentsURL = base
        let store = EncounterStore(baseURL: base)
        state.encounterStore = store
        try await store.startNewCasualty(id: state.casualtyId, startUnix: 1)
        await state.processWithEngineForTest("Heart rate one ten.")
        // Read the active casualty's file back through a fresh store.
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        let log = try XCTUnwrap(loaded).log
        XCTAssertTrue(log.events.contains {
            if case .deterministicFact(let p) = $0, case .vitalsHR(110) = p.delta { return true }; return false
        }, "the HR fact must be on disk immediately after the transcript line")
    }
}
