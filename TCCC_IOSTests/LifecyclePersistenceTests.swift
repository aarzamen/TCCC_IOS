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

    func testNewCasualtyContinuesNumberingAfterRelaunch() async throws {
        let firstLaunch = await makeState()
        await firstLaunch.newPatient()
        XCTAssertEqual(firstLaunch.casualtyId, "C-05")

        let secondLaunch = await makeState()
        XCTAssertEqual(secondLaunch.casualtyId, "C-05")
        await secondLaunch.newPatient()
        XCTAssertEqual(secondLaunch.casualtyId, "C-06", "restoring an encounter must also recover its number")
        await secondLaunch.newPatient()
        XCTAssertEqual(secondLaunch.casualtyId, "C-07")

        let thirdLaunch = await makeState()
        await thirdLaunch.newPatient()
        XCTAssertEqual(thirdLaunch.casualtyId, "C-08", "repeated relaunches must not reuse C-05")
    }

    func testNewCasualtyAdvancesBeyondArchivedHigherNumberWithoutRenumberingActive() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-12", startUnix: 1)
        try await store.appendToActive([.asrSegment(.init(id: "archived-source", patientId: "PATIENT_1",
            timestampUnix: 1, text: "synthetic archive", backend: "engine", isFinal: true))])
        try await store.archiveActive(endedUnix: 2)
        try await store.startNewCasualty(id: "C-08", startUnix: 3)
        let archivedDirectory = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath:
            base.appendingPathComponent("encounters").path).first { $0.hasPrefix("C-12_") })
        let archivedLog = base.appendingPathComponent("encounters/\(archivedDirectory)/events.jsonl")
        let originalBytes = try Data(contentsOf: archivedLog)

        let state = await makeState()
        XCTAssertEqual(state.casualtyId, "C-08", "recovery must preserve the existing encounter label")
        await state.newPatient()
        XCTAssertEqual(state.casualtyId, "C-13", "allocation must include archived encounters")
        XCTAssertEqual(try Data(contentsOf: archivedLog), originalBytes, "historic records are not rewritten")
        let active = try await EncounterStore(baseURL: base).loadActiveEncounter()
        XCTAssertEqual(active?.casualtyId, "C-13")
    }

    func testLaunchWithOnlyArchivedEncountersStartsAboveTheirNumbers() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-12", startUnix: 1)
        try await store.archiveActive(endedUnix: 2)

        let state = await makeState()
        XCTAssertEqual(state.casualtyId, "C-13", "no active encounter must not reset an existing archive to C-04")
        await state.newPatient()
        XCTAssertEqual(state.casualtyId, "C-14")
    }

    func testNewCasualtyDoesNotResetOrOverwriteUnreadableNumberingManifest() async throws {
        let state = await makeState()
        await state.processWithEngineForTest("Heart rate one ten.")
        let priorId = state.casualtyId
        let manifestURL = base.appendingPathComponent("encounters/manifest.json")
        let corruptBytes = Data("{incomplete manifest".utf8)
        try corruptBytes.write(to: manifestURL)

        await state.newPatient()

        XCTAssertEqual(state.casualtyId, priorId, "unknown used numbers must not allocate a reused label")
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 110, "failed allocation must preserve current care")
        XCTAssertEqual(try Data(contentsOf: manifestURL), corruptBytes, "an unreadable manifest must not be overwritten")
        XCTAssertTrue(state.transcript.contains { $0.text.contains("FAILED") }, "failure must be visible")
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
