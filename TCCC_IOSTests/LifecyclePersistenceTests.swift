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

    func testNewCasualtyPreservesPriorEncounterFile() async throws {
        let state = await makeState()
        await state.processWithEngineForTest("GSW right thigh.")
        let priorId = state.casualtyId
        await state.newPatient()
        // The prior casualty's events.jsonl must still exist on disk.
        let enc = base.appendingPathComponent("encounters")
        let dirs = try FileManager.default.contentsOfDirectory(atPath: enc.path)
        XCTAssertTrue(dirs.contains { $0.hasPrefix("\(priorId)_") }, "prior casualty dir must be preserved")
        XCTAssertNotEqual(state.casualtyId, priorId, "a new casualty id is assigned")
    }

    func testWipePurgesPriorDataAndRearmsFreshCasualty() async throws {
        let state = await makeState()
        await state.processWithEngineForTest("GSW right thigh.")
        XCTAssertEqual(state.primaryPatient?.mechanismOfInjury, "GSW")

        await state.wipeSession()

        // Post-WIPE in-memory state is clean (prior PHI gone).
        XCTAssertNil(state.primaryPatient?.mechanismOfInjury, "post-WIPE state must be clean")

        // A fresh casualty is armed AND persisting: a new app launch recovers an
        // encounter that has NONE of the prior casualty's facts — only the fresh seed.
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        let log = try XCTUnwrap(loaded, "WIPE must re-arm a fresh persisting casualty").log
        XCTAssertFalse(log.events.contains {
            if case .deterministicFact(let p) = $0, case .mechanismOfInjury("GSW") = p.delta { return true }
            return false
        }, "the prior casualty's facts must be purged from disk")
        XCTAssertTrue(log.events.contains {
            if case .lifecycle(let p) = $0, p.kind == .encounterStarted { return true }
            return false
        }, "the fresh casualty's seed must be on disk (persistence re-armed)")
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
