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

    // B5 adds the load()-based helper (load() now exists); B6 reuses it.
    private func makeState() async -> AppState {
        let state = AppState()
        state.documentsURL = base
        await state.load()        // no prior active → opens a fresh casualty + flushes the seed
        return state
    }

    func testCrashRecoveryReplaysInProgressEncounter() async throws {
        // Simulate active care + crash: write events via one AppState, then load a fresh one.
        let pre = await makeState()
        await pre.processWithEngineForTest("GSW right thigh. Heart rate one ten.")
        let expected = pre.primaryPatient

        // Fresh AppState (new app launch) pointed at the same dir.
        let post = AppState()
        post.documentsURL = base
        await post.load()
        XCTAssertEqual(post.primaryPatient?.vitals.hr, 110, "in-progress HR must survive relaunch")
        XCTAssertEqual(post.primaryPatient?.mechanismOfInjury, expected?.mechanismOfInjury)
        XCTAssertEqual(post.casualtyId, "C-04")
    }

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
