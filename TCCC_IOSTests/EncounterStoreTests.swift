// TCCC_IOSTests/EncounterStoreTests.swift
import XCTest
import TCCCExtractor
@testable import TCCC_IOS

final class EncounterStoreTests: XCTestCase {
    private var base: URL!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("estore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func event(_ id: String) -> EncounterEvent {
        .asrSegment(.init(id: id, patientId: "PATIENT_1", timestampUnix: 1, text: "x", backend: "engine", isFinal: true))
    }

    func testAppendThenLoadRoundTrips() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-1"), event("seg-2")])
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        let unwrapped = try XCTUnwrap(loaded)
        XCTAssertEqual(unwrapped.casualtyId, "C-04")
        XCTAssertEqual(unwrapped.log.events.map(\.id), ["seg-1", "seg-2"])
    }

    func testArchivedEncounterIsNotLoadedAsActive() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-1")])
        try await store.archiveActive(endedUnix: 200)
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        XCTAssertNil(loaded, "an archived casualty must not be replayed as in-progress")
    }

    func testCorruptTailIsTolerated() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-1"), event("seg-2")])
        // Simulate a crash mid-write: append a truncated JSON line.
        // Discover the dir (the name now carries a collision-proof UUID suffix).
        let enc = base.appendingPathComponent("encounters")
        let dirName = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: enc.path)
            .first { $0.hasPrefix("C-04_") })
        let dir = enc.appendingPathComponent(dirName, isDirectory: true)
        let file = dir.appendingPathComponent("events.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"asrSegment\":{\"id\":\"seg-3\"".utf8)); try handle.close()
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        let unwrapped = try XCTUnwrap(loaded)
        XCTAssertEqual(unwrapped.log.events.map(\.id), ["seg-1", "seg-2"], "the truncated tail line is skipped")
    }

    func testPurgeAllRemovesTree() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-1")])
        try await store.purgeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("encounters").path))
    }

    /// Regression (whole-branch review #1): End Care reuses the same casualtyId with
    /// startUnix=now, so a same-integer-second rotation must NOT reuse the just-archived
    /// directory — else the fresh "active" casualty inherits the ended casualty's PHI.
    func testSameIdSameSecondRotationDoesNotInheritArchivedEvents() async throws {
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-1")])
        try await store.archiveActive(endedUnix: 100)
        // Same id, same integer second as the just-archived casualty.
        try await store.startNewCasualty(id: "C-04", startUnix: 100)
        try await store.appendToActive([event("seg-2")])
        let loaded = try await EncounterStore(baseURL: base).loadActiveEncounter()
        let log = try XCTUnwrap(loaded).log
        XCTAssertEqual(log.events.map(\.id), ["seg-2"],
                       "the fresh casualty must not inherit the archived casualty's events")
    }
}
