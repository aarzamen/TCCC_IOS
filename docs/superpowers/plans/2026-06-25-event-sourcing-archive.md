# Event-Sourcing Durable Archive (Sub-cycle B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Persist the per-casualty `EncounterEvent` log to disk, encrypted (`NSFileProtectionComplete`), continuously; replay an in-progress encounter on launch; retain past casualties in a manifest-indexed archive; wire New Casualty / End Care to PRESERVE and WIPE to PURGE.

**Architecture:** TCCCKit stays in-memory-pure (gains only a restore seam + a lifecycle-marker method). All disk I/O lives in an app-layer `EncounterStore` actor + a new `ProtectedWrite.appendLine`. `AppState.refreshPatientSnapshot()` flushes new events after every engine mutation (cursor-guarded). `TCCC_IOSApp` replays on launch via `.task`.

**Tech Stack:** Swift 6 strict concurrency, `actor` isolation, `Codable` JSONL, `FileHandle` append, XCTest with injected temp directories.

**Spec:** `docs/superpowers/specs/2026-06-25-event-sourcing-archive-design.md`.

## Global Constraints

- **752 TCCCKit + 72 app tests stay green at every task boundary** (plus each task's new tests).
- **TCCCKit adds NO disk I/O / Foundation-file APIs.** Persistence is app-layer only. The engine's only new surface: `restore(_:)`, `recordLifecycle(_:timestamp:)`, the `lifecycleCount` counter, and the B0 `ensurePatientExists` change.
- **Encryption at rest:** every file AND directory written carries `FileProtectionType.complete` / `NSFileProtectionComplete`; `appendLine` re-asserts protection after every write. Device-validated in B7.
- **Continuous persistence:** after any committed event, it is on disk before the next user action; cursor-guarded so nothing is written twice and replayed events aren't re-persisted.
- **PRESERVE:** New Casualty / End Care never delete a prior casualty's `events.jsonl`. **PURGE:** WIPE deletes the whole `encounters/` tree and asserts `!exists`.
- **The domain model is untouched** — no fields added to `PatientState`; casualty timing lives in the manifest. The A-cycle equivalence tests must stay green.
- **Determinism:** the B0 lifecycle event's timestamp is threaded from the processing timestamp (not a fresh `Date()` inside `ensurePatientExists`).
- **`Codable` strategy:** `EncounterStore`'s encoder/decoder both use `.dateDecodingStrategy`/`.dateEncodingStrategy = .secondsSince1970` so `Intervention.timestamp` round-trips exactly (the restore round-trip test gates this).

**Build / verify commands**
- TCCCKit (B0, B3): `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`
- App (B1, B2, B4, B5, B6): regenerate + test on the working destination:
  ```bash
  cd /Users/ama/TCCC_IOS && xcodegen generate && \
  xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
    -destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' \
    -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation \
    -only-testing:TCCC_IOSTests 2>&1 | tail -40
  ```
  - bare `id=` / `generic/platform=iOS Simulator` FAIL; class-level `-only-testing:Target/Class` reports 0 — use the full target or `Target/Class/method`.
  - **Any task adding a NEW app file must `git add TCCC_IOS.xcodeproj/project.pbxproj`** after `xcodegen generate`.

---

## File Structure

**New (app):**
- `TCCC_IOS/App/EncounterStore.swift` — `EncounterStore` actor + `EncounterManifest` Codable struct.
- `TCCC_IOSTests/ProtectedWriteAppendTests.swift` — B1.
- `TCCC_IOSTests/EncounterStoreTests.swift` — B2.
- `TCCC_IOSTests/LifecyclePersistenceTests.swift` — B4/B5/B6.

**Modified (TCCCKit):**
- `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` — B0 (`lifecycleCount`, `ensurePatientExists(_:timestamp:)`), B3 (`restore`, `recordLifecycle`).
- `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift` — B0 (`project` ensures rows for `.encounterStarted`).
- `Packages/TCCCKit/Tests/TCCCExtractorTests/{LogEquivalenceTests,EngineRestoreTests}.swift` — B0/B3.

**Modified (app):**
- `TCCC_IOS/App/ProtectedWrite.swift` — B1 (`appendLine`).
- `TCCC_IOS/App/AppState.swift` — B4 (`documentsURL`, `encounterStore`, `persistedCursor`, `persistNewEvents`, `refreshPatientSnapshot` edit, `load`), B6 (lifecycle method rewrites).
- `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` — B4 (persist after reject).
- `TCCC_IOS/App/ConfirmationAction.swift` — B6 (copy).
- `TCCC_IOS/TCCC_IOSApp.swift` — B5 (`.task`).
- `TCCC_IOSTests/LifecycleAffordanceTests.swift` — B6 (copy assertions).

---

## Task B0: Key-set fix — lifecycle-on-create + project ensures rows (TCCCKit)

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift`
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift`
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift` (add)

**Interfaces:**
- Produces: `lifecycleCount` engine counter; `ensurePatientExists(_:timestamp:)` emits `.encounterStarted` on creation; `project` ensures a row per `.encounterStarted`. Consumed by B3 (counter resume) + replay.

- [ ] **Step 1: Write the failing test** (append to `LogEquivalenceTests.swift`)

```swift
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
```

- [ ] **Step 2: Run RED**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter LogEquivalenceTests`
Expected: the new test FAILS (no lifecycle event for PATIENT_2; the `contains` assertion fails).

- [ ] **Step 3: Implement**

In `PatientStateEngine.swift`, add the counter and thread the timestamp:

```swift
// add beside asrCount/factCount (line ~46):
private var lifecycleCount = 1   // init seeds "lc-1"
```

Change `ensurePatientExists` to accept a timestamp and emit a lifecycle event on creation:

```swift
private func ensurePatientExists(_ patientId: String, timestamp: Double = 0) {
    if patients[patientId] == nil {
        patients[patientId] = PatientState(patientId: patientId)
        lifecycleCount += 1
        log.append(.lifecycle(.init(
            id: "lc-\(lifecycleCount)", patientId: patientId,
            timestampUnix: timestamp, kind: .encounterStarted)))
    }
}
```

Thread the processing timestamp at the call sites in `processTranscript` (lines 98, 102 — pass `unixTimestamp`) and `recordOperatorAcceptedFact` (line 165 — pass `unix`):

```swift
// line 96-98:
if let newID = switcher.detectSwitch(in: sentence) {
    currentPatientID = newID
    ensurePatientExists(currentPatientID, timestamp: unixTimestamp)
}
// line 102:
ensurePatientExists(currentPatientID, timestamp: unixTimestamp)
```
```swift
// in recordOperatorAcceptedFact, line 165:
ensurePatientExists(patientId, timestamp: unix)
```
(`apply(_:to:)` line 148 keeps the default `timestamp: 0` — it's test-only.)

In `PatientStateProjection.swift`, change `project`'s skip arm so `.encounterStarted` ensures a row:

```swift
// replace: case .asrSegment, .operatorRejectedFact, .lifecycle: continue
case .asrSegment, .operatorRejectedFact:
    continue
case .lifecycle(let p):
    if p.kind == .encounterStarted { ensure(p.patientId) }
    continue
```

- [ ] **Step 4: Run GREEN + full suite**

Run: `--filter LogEquivalenceTests` → all pass. Then `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → all green (was 752; +1 here). **Confirm the equivalence/scenario tests still pass** — the extra lifecycle events are inert in `project` for state, and `project`'s key-set now matches the imperative dict exactly. If `testEveryFieldWriteMapsToADelta` or scenario equivalence breaks, investigate (it shouldn't — lifecycle events don't carry deltas).

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Sources/TCCCExtractor/PatientStateProjection.swift Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
git commit -m "fix(event-sourcing): emit encounterStarted per patient + project ensures rows (key-set invariant)"
```

---

## Task B1: ProtectedWrite.appendLine (app)

**Files:**
- Modify: `TCCC_IOS/App/ProtectedWrite.swift`
- Test: `TCCC_IOSTests/ProtectedWriteAppendTests.swift` (create)

**Interfaces:**
- Produces: `static func appendLine(_ line: String, to url: URL) throws`. Consumed by B2.

- [ ] **Step 1: Write the failing test**

```swift
// TCCC_IOSTests/ProtectedWriteAppendTests.swift
import XCTest
@testable import TCCC_IOS

final class ProtectedWriteAppendTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pwtest-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAppendLineCreatesDirAndFileAndRoundTrips() throws {
        let file = dir.appendingPathComponent("nested/events.jsonl")
        try ProtectedWrite.appendLine("{\"a\":1}", to: file)
        try ProtectedWrite.appendLine("{\"b\":2}", to: file)
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(contents, "{\"a\":1}\n{\"b\":2}\n")
    }

    func testAppendedFileHasCompleteProtection() throws {
        let file = dir.appendingPathComponent("events.jsonl")
        try ProtectedWrite.appendLine("x", to: file)
        let values = try file.resourceValues(forKeys: [.fileProtectionKey])
        // On the simulator this may report nil/none — assert it is NOT explicitly unprotected.
        // Device validation (B7) confirms .complete. Here we assert the call path set a value
        // when the platform supports it.
        if let p = values.fileProtection {
            XCTAssertEqual(p, .complete)
        }
    }
}
```

- [ ] **Step 2: Run RED**

Run the app target (full): expect `testAppendLineCreatesDirAndFileAndRoundTrips` to FAIL (`appendLine` undefined → compile error).

- [ ] **Step 3: Implement** (add to `ProtectedWrite`)

```swift
/// Append one line (+ newline) to a file, creating the parent dir and file with
/// complete protection if needed, and re-asserting NSFileProtectionComplete after
/// the write. Used for the encrypted per-casualty event JSONL.
static func appendLine(_ line: String, to url: URL) throws {
    let fm = FileManager.default
    let dir = url.deletingLastPathComponent()
    if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
    }
    if !fm.fileExists(atPath: url.path) {
        try createEmpty(at: url)
    }
    let handle = try FileHandle(forWritingTo: url)
    do {
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.close()
    } catch {
        try? handle.close()
        throw error
    }
    try markProtected(at: url)
}
```

- [ ] **Step 4: Run GREEN**

App target full run → both new tests pass; existing 72 stay green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add TCCC_IOS/App/ProtectedWrite.swift TCCC_IOSTests/ProtectedWriteAppendTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(persistence): ProtectedWrite.appendLine — encrypted FileHandle append for JSONL"
```

---

## Task B2: EncounterStore actor + manifest (app)

**Files:**
- Create: `TCCC_IOS/App/EncounterStore.swift`
- Test: `TCCC_IOSTests/EncounterStoreTests.swift` (create)

**Interfaces:**
- Produces: `actor EncounterStore` with `init(baseURL:)`, `startNewCasualty(id:startUnix:)`, `appendToActive(_:)`, `archiveActive(endedUnix:)`, `purgeAll()`, `loadActiveEncounter() -> (casualtyId,log)?`; `struct EncounterManifest`. Consumed by B4/B5/B6.
- Consumes: `EncounterEvent`/`EncounterLog` (TCCCExtractor), `ProtectedWrite.appendLine` (B1).

- [ ] **Step 1: Write the failing test**

```swift
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
        let dir = base.appendingPathComponent("encounters/C-04_100", isDirectory: true)
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
}
```

- [ ] **Step 2: Run RED** → `EncounterStore` undefined.

- [ ] **Step 3: Implement**

```swift
// TCCC_IOS/App/EncounterStore.swift
import Foundation
import TCCCExtractor

/// On-disk index of all encounters. Source of truth is each casualty's
/// events.jsonl; this manifest is a rebuildable pointer to the active one.
struct EncounterManifest: Codable, Sendable {
    var schemaVersion: Int = 1
    var activeCasualtyId: String?
    var encounters: [Entry] = []

    struct Entry: Codable, Sendable {
        let casualtyId: String
        let dirName: String
        let startUnix: Double
        var endedUnix: Double?
        var archivedUnix: Double?
        var status: String          // "active" | "archived"
    }
}

/// App-layer owner of all encounter persistence. Serial actor ⇒ ordered,
/// off-MainActor disk writes. TCCCKit never touches disk.
actor EncounterStore {
    private let baseURL: URL
    private var activeDir: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        self.encoder = e; self.decoder = d
    }

    private var encountersDir: URL { baseURL.appendingPathComponent("encounters", isDirectory: true) }
    private var manifestURL: URL { encountersDir.appendingPathComponent("manifest.json") }

    func startNewCasualty(id: String, startUnix: Double) throws {
        try ensureEncountersDir()
        let dirName = "\(id)_\(Int(startUnix))"
        let dir = encountersDir.appendingPathComponent(dirName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        activeDir = dir
        var m = (try? loadManifest()) ?? EncounterManifest()
        m.encounters.append(.init(casualtyId: id, dirName: dirName, startUnix: startUnix,
            endedUnix: nil, archivedUnix: nil, status: "active"))
        m.activeCasualtyId = id
        try saveManifest(m)
    }

    func appendToActive(_ events: [EncounterEvent]) throws {
        guard let dir = activeDir else { return }
        let file = dir.appendingPathComponent("events.jsonl")
        for event in events {
            let line = String(decoding: try encoder.encode(event), as: UTF8.self)
            try ProtectedWrite.appendLine(line, to: file)
        }
    }

    func archiveActive(endedUnix: Double) throws {
        guard var m = try? loadManifest(), let activeId = m.activeCasualtyId else { return }
        if let i = m.encounters.firstIndex(where: { $0.casualtyId == activeId && $0.status == "active" }) {
            m.encounters[i].archivedUnix = endedUnix
            m.encounters[i].status = "archived"
        }
        m.activeCasualtyId = nil
        try saveManifest(m)
        activeDir = nil
    }

    func purgeAll() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: encountersDir.path) {
            try fm.removeItem(at: encountersDir)
        }
        activeDir = nil
    }

    func loadActiveEncounter() throws -> (casualtyId: String, log: EncounterLog)? {
        guard let m = try? loadManifest(), let activeId = m.activeCasualtyId,
              let entry = m.encounters.first(where: { $0.casualtyId == activeId && $0.status == "active" })
        else { return nil }
        let dir = encountersDir.appendingPathComponent(entry.dirName, isDirectory: true)
        activeDir = dir
        return (activeId, loadLog(from: dir.appendingPathComponent("events.jsonl")))
    }

    // MARK: - Helpers

    private func ensureEncountersDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: encountersDir.path) {
            try fm.createDirectory(at: encountersDir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
        }
    }

    private func loadManifest() throws -> EncounterManifest {
        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode(EncounterManifest.self, from: data)
    }

    private func saveManifest(_ m: EncounterManifest) throws {
        try ProtectedWrite.data(try encoder.encode(m), to: manifestURL)
    }

    /// Decode a JSONL log, tolerating a truncated final line (crash mid-write):
    /// any line that fails to decode is skipped.
    private func loadLog(from url: URL) -> EncounterLog {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return EncounterLog() }
        var log = EncounterLog()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(EncounterEvent.self, from: Data(line.utf8)) {
                log.append(event)
            }
        }
        return log
    }
}
```

- [ ] **Step 4: Run GREEN** → 4 new tests pass; app suite green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add TCCC_IOS/App/EncounterStore.swift TCCC_IOSTests/EncounterStoreTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(persistence): EncounterStore actor — per-casualty JSONL + manifest + corrupt-tail tolerance"
```

---

## Task B3: Engine restore seam + lifecycle marker (TCCCKit)

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift`
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/EngineRestoreTests.swift` (create)

**Interfaces:**
- Produces: `func restore(_ log: EncounterLog)`, `func recordLifecycle(_ kind: LifecyclePayload.Kind, timestamp:)`. Consumed by B5 (replay) + B6 (lifecycle markers).

- [ ] **Step 1: Write the failing test**

```swift
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
        XCTAssertEqual(await restored.snapshot(), savedSnapshot, "restore must reproduce projected state exactly")

        // A subsequent mutation must not reuse an id already in the restored log.
        await restored.processTranscript("Blood pressure ninety over sixty.")
        let ids = await restored.snapshotLog().events.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no id collisions after restore")
    }

    func testRecordLifecycleAppendsInertMarker() async throws {
        let engine = PatientStateEngine.standard()
        let before = await engine.snapshot()
        await engine.recordLifecycle(.encounterEnded)
        XCTAssertEqual(await engine.snapshot(), before, "a lifecycle marker must not change state")
        XCTAssertTrue(await engine.snapshotLog().events.contains {
            if case .lifecycle(let p) = $0, p.kind == .encounterEnded { return true }; return false
        })
    }
}
```

- [ ] **Step 2: Run RED** → `restore`/`recordLifecycle` undefined.

- [ ] **Step 3: Implement** (add to `PatientStateEngine`, after `recordOperatorRejectedFact`)

```swift
// MARK: - Restore + lifecycle (sub-cycle B)

/// Re-seat the engine from a persisted log (replay-on-launch). Resumes id counters
/// from per-type event counts (ids are sequential, so count == max) so subsequent
/// events don't collide with replayed ones.
public func restore(_ restoredLog: EncounterLog) {
    log = restoredLog
    patients = Self.project(restoredLog)
    var asr = 0, fact = 0, op = 0, life = 0
    var lastAsrPatient: String?
    for event in restoredLog.events {
        switch event {
        case .asrSegment(let p):            asr += 1; lastAsrPatient = p.patientId
        case .deterministicFact:            fact += 1
        case .operatorAcceptedFact,
             .operatorRejectedFact:         op += 1
        case .lifecycle:                    life += 1
        }
    }
    asrCount = asr; factCount = fact; opCount = op; lifecycleCount = life
    currentPatientID = lastAsrPatient ?? "PATIENT_1"
}

/// Append an audit-only lifecycle marker (End Care / archival). `.encounterEnded`
/// and `.archived` are inert in `project`, so no re-projection is needed.
public func recordLifecycle(_ kind: LifecyclePayload.Kind, timestamp: Date = Date()) {
    lifecycleCount += 1
    log.append(.lifecycle(.init(
        id: "lc-\(lifecycleCount)", patientId: currentPatientID,
        timestampUnix: timestamp.timeIntervalSince1970, kind: kind)))
}
```

- [ ] **Step 4: Run GREEN + full suite** → 2 new tests pass; full TCCCKit green.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/EngineRestoreTests.swift
git commit -m "feat(event-sourcing): engine restore seam + lifecycle marker (replay groundwork)"
```

---

## Task B4: Continuous persistence wiring (app)

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (add `documentsURL`, `encounterStore`, `persistedCursor`, `persistNewEvents`, edit `refreshPatientSnapshot`)
- Modify: `TCCC_IOS/Intelligence/GraniteReviewQueue.swift` (persist after reject)
- Test: `TCCC_IOSTests/LifecyclePersistenceTests.swift` (create)

**Interfaces:**
- Produces: `AppState.persistNewEvents() async`, `AppState.documentsURL`, `AppState.encounterStore`, `AppState.persistedCursor`. Consumed by B5/B6.

- [ ] **Step 1: Write the failing test**

```swift
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
```

> `processWithEngineForTest` is a thin `#if DEBUG` test shim added to AppState that calls the private `processWithEngine` (Step 3). If the implementer prefers, drop `private` from `processWithEngine` (make it `internal`) and call it directly.

- [ ] **Step 2: Run RED** → `documentsURL`/`load`/persistence undefined.

- [ ] **Step 3: Implement** in `AppState.swift`:

Add stored properties (near `engine`, line ~449):

```swift
/// Base directory for casualty persistence. Injectable for tests; defaults to Documents.
var documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: NSTemporaryDirectory())
/// On-disk encounter store (nil until `load()` configures it).
var encounterStore: EncounterStore?
/// Count of engine log events already flushed to disk. Cursor-guards persistence.
private(set) var persistedCursor: Int = 0
```

Add the persistence method:

```swift
/// Flush any engine-log events beyond the cursor to the active casualty's file.
/// Cursor-guarded ⇒ idempotent and safe to call after every engine mutation.
func persistNewEvents() async {
    guard let store = encounterStore else { return }
    let log = await engine.snapshotLog()
    guard log.events.count > persistedCursor else { return }
    let new = Array(log.events[persistedCursor...])
    do {
        try await store.appendToActive(new)
        persistedCursor = log.events.count
    } catch {
        appendSystem("PERSIST FAILED · \(error.localizedDescription)")
    }
}
```

Fold persistence into the post-mutation chokepoint — append one line at the end of `refreshPatientSnapshot()` (line ~540, after `appendVitalsSnapshot()`):

```swift
    appendVitalsSnapshot()
    await persistNewEvents()        // continuous persistence (cursor-guarded)
}
```

Add the test shim (or make `processWithEngine` internal):

```swift
#if DEBUG
func processWithEngineForTest(_ text: String) async { await processWithEngine(text, timestamp: Date()) }
#endif
```

In `GraniteReviewQueue.swift`, persist after a rejection is recorded (reject doesn't call `refreshPatientSnapshot`). In `rejectGraniteReviewItem`'s `Task`, after the loop that records rejections, add:

```swift
    await persistNewEvents()
```

- [ ] **Step 4: Run GREEN** → new test passes; app suite green (the default `AppState()` in other tests has `encounterStore == nil`, so `persistNewEvents` no-ops — they stay green).

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add TCCC_IOS/App/AppState.swift TCCC_IOS/Intelligence/GraniteReviewQueue.swift TCCC_IOSTests/LifecyclePersistenceTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(persistence): continuous event persistence after each engine mutation (cursor-guarded)"
```

---

## Task B5: Replay-on-launch (app)

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (add `load()`)
- Modify: `TCCC_IOS/TCCC_IOSApp.swift` (`.task`)
- Test: `TCCC_IOSTests/LifecyclePersistenceTests.swift` (add)

**Interfaces:**
- Produces: `AppState.load() async`. Consumed by `TCCC_IOSApp`.

- [ ] **Step 1: Write the failing test** (append to `LifecyclePersistenceTests`)

```swift
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
```

- [ ] **Step 2: Run RED** → recovery fails (no `load` replay yet / `post.load()` opens a NEW casualty instead of recovering).

- [ ] **Step 3: Implement** — `AppState.load()`:

```swift
/// Replay-on-launch: recover an in-progress encounter from disk, or open a fresh
/// casualty dir for this session. Call once at app launch.
func load() async {
    let store = EncounterStore(baseURL: documentsURL)
    encounterStore = store
    do {
        if let (id, log) = try await store.loadActiveEncounter() {
            casualtyId = id
            await engine.restore(log)
            persistedCursor = log.events.count
            await refreshPatientSnapshot()        // cursor up-to-date ⇒ persists nothing
            appendSystem("RECOVERED · \(id) · \(log.events.count) events replayed")
        } else {
            try await store.startNewCasualty(id: casualtyId, startUnix: Date().timeIntervalSince1970)
            persistedCursor = 0
            await persistNewEvents()              // flush the fresh engine's lc-1 seed
        }
    } catch {
        appendSystem("PERSIST INIT FAILED · \(error.localizedDescription)")
    }
}
```

`TCCC_IOSApp.swift` — replay before/as the UI settles:

```swift
var body: some Scene {
    WindowGroup {
        ContentView(state: state)
            .task { await state.load() }
    }
}
```

- [ ] **Step 4: Run GREEN** → recovery test passes; app suite green.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add TCCC_IOS/App/AppState.swift TCCC_IOS/TCCC_IOSApp.swift TCCC_IOSTests/LifecyclePersistenceTests.swift TCCC_IOS.xcodeproj/project.pbxproj
git commit -m "feat(persistence): replay-on-launch — recover in-progress encounter from disk"
```

---

## Task B6: Lifecycle PRESERVE/PURGE rewrite (app)

**Files:**
- Modify: `TCCC_IOS/App/AppState.swift` (make `newPatient`/`endCurrentCare`/`wipeSession` async + archival/purge), `ConfirmationAction.swift` (copy), `confirmPending` + call sites (await)
- Modify: `TCCC_IOSTests/LifecycleAffordanceTests.swift` (copy assertions)
- Test: `TCCC_IOSTests/LifecyclePersistenceTests.swift` (add)

**Interfaces:**
- Produces: async `newPatient()/endCurrentCare()/wipeSession()`; updated `ConfirmationAction.detail`.

- [ ] **Step 1: Write the failing test** (append to `LifecyclePersistenceTests`)

```swift
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

func testWipePurgesEntireArchive() async throws {
    let state = await makeState()
    await state.processWithEngineForTest("GSW right thigh.")
    await state.wipeSession()
    XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent("encounters").path),
                   "WIPE must delete the entire encounters tree")
}
```

- [ ] **Step 2: Run RED** → `newPatient`/`wipeSession` aren't async / don't persist-archive yet.

- [ ] **Step 3: Implement** — convert the three methods to `async` and wrap the existing in-memory reset with archival/purge. Keep the EXISTING in-memory reset bodies verbatim; add the disk steps around them. `newPatient()`:

```swift
func newPatient() async {
    let now = Date().timeIntervalSince1970
    await engine.recordLifecycle(.archived)
    await persistNewEvents()                                  // flush marker to OLD file
    try? await encounterStore?.archiveActive(endedUnix: now)  // manifest: old → archived
    // --- existing in-memory reset (verbatim), which sets a fresh engine + new casualtyId ---
    autoCleanTask?.cancel(); autoCleanTask = nil; lastCleanedAt = nil
    voiceCommandTask?.cancel(); voiceCommandTask = nil; pendingVoiceCommand = nil
    let oldId = casualtyId
    casualtyCounter += 1
    casualtyId = String(format: "C-%02d", casualtyCounter)
    transcript.removeAll(); transcriptLedger = TranscriptSegmentLedger(); partialTranscript = ""
    recognitionError = nil; primaryPatient = nil; allPatients.removeAll(); sessionStart = Date()
    engine = PatientStateEngine.standard()
    lastRecordingURL = nil; encounterNarrative = nil; zmistNarrative = nil; transcriptCleaned = nil
    vitalsLog.removeAll(); lastMedevacTransmitTime = nil; graniteReviewQueue.removeAll(); lastConflictMessage = nil
    // --- open the new casualty on disk + flush its seed ---
    persistedCursor = 0
    try? await encounterStore?.startNewCasualty(id: casualtyId, startUnix: now)
    await persistNewEvents()                                  // flush new engine's lc-1 seed
    appendSystem("NEW CASUALTY · \(casualtyId) · \(oldId) archived")
}
```

`endCurrentCare()` — same archival, no new casualty (keep its existing in-memory reset verbatim, prefixed):

```swift
func endCurrentCare() async {
    let now = Date().timeIntervalSince1970
    await engine.recordLifecycle(.encounterEnded)
    await persistNewEvents()
    try? await encounterStore?.archiveActive(endedUnix: now)
    // --- existing in-memory reset (verbatim) ---
    autoCleanTask?.cancel(); autoCleanTask = nil; lastCleanedAt = nil
    voiceCommandTask?.cancel(); voiceCommandTask = nil; pendingVoiceCommand = nil
    let endedId = casualtyId
    appendSystem("CARE ENDED · \(endedId) · handoff finalized")
    transcript.removeAll(where: { $0.speaker != .system || !$0.text.contains("CARE ENDED") })
    transcriptLedger = TranscriptSegmentLedger(); partialTranscript = ""
    primaryPatient = nil; allPatients.removeAll(); engine = PatientStateEngine.standard()
    lastRecordingURL = nil; encounterNarrative = nil; zmistNarrative = nil; transcriptCleaned = nil
    vitalsLog.removeAll(); lastMedevacTransmitTime = nil; graniteReviewQueue.removeAll(); lastConflictMessage = nil
    // End Care leaves a clean slate but keeps persistence live for the next casualty
    // under the same id: re-open a fresh dir + flush the new engine's seed.
    persistedCursor = 0
    try? await encounterStore?.startNewCasualty(id: casualtyId, startUnix: now)
    await persistNewEvents()
}
```

`wipeSession()` — purge then the existing reset:

```swift
func wipeSession() async {
    do {
        try await encounterStore?.purgeAll()
        let enc = documentsURL.appendingPathComponent("encounters")
        assert(!FileManager.default.fileExists(atPath: enc.path), "WIPE must purge the archive")
        if FileManager.default.fileExists(atPath: enc.path) {
            appendSystem("WIPE INCOMPLETE · archive still present")
        }
    } catch {
        appendSystem("WIPE FAILED · \(error.localizedDescription)")
    }
    // --- existing in-memory reset (verbatim) ---
    autoCleanTask?.cancel(); autoCleanTask = nil; lastCleanedAt = nil
    voiceCommandTask?.cancel(); voiceCommandTask = nil; pendingVoiceCommand = nil
    transcript.removeAll(); transcriptLedger = TranscriptSegmentLedger(); partialTranscript = ""
    recognitionError = nil; primaryPatient = nil; allPatients.removeAll(); sessionStart = Date()
    engine = PatientStateEngine.standard()
    casualtyCounter = 4; casualtyId = "C-04"
    lastRecordingURL = nil; encounterNarrative = nil; zmistNarrative = nil; transcriptCleaned = nil
    vitalsLog.removeAll(); lastMedevacTransmitTime = nil; graniteReviewQueue.removeAll(); lastConflictMessage = nil
    // After reset, re-open a fresh casualty dir so persistence resumes (the old
    // tree — incl. the prior C-04 — was just purged; the new dir gets a fresh timestamp):
    persistedCursor = 0
    try? await encounterStore?.startNewCasualty(id: casualtyId, startUnix: Date().timeIntervalSince1970)
    await persistNewEvents()
}
```

Make `confirmPending()` async and await the methods:

```swift
func confirmPending() async {
    guard let action = pendingConfirmation else { return }
    pendingConfirmation = nil
    switch action {
    case .newPatient: await newPatient()
    case .endCare:    await endCurrentCare()
    case .wipe:       await wipeSession()
    }
}
```

Update every caller of `confirmPending()` / the lifecycle methods (the confirmation UI button, the voice-command auto-fire path, the footer hold-to-confirm) to `await` inside a `Task { @MainActor in … }`. Find them with `grep -rn "confirmPending\|\.newPatient()\|\.endCurrentCare()\|\.wipeSession()" TCCC_IOS/` and wrap each call site. (The `wipeHoldGesture` already runs in a `Task { @MainActor in … }` — change `state.wipeSession()` to `await state.wipeSession()`.)

Update `ConfirmationAction.detail` copy (PRESERVE language):

```swift
var detail: String {
    switch self {
    case .newPatient:
        return "Archive this casualty's record and open a new one. Operator profile preserved."
    case .endCare:
        return "Archive this casualty's record and mark care complete. Casualty counter not incremented."
    case .wipe:
        return "Permanently purge ALL archived casualties, transcripts, vitals, and exports. This cannot be undone."
    }
}
```

Update `LifecycleAffordanceTests` to assert the PRESERVE copy (archive language present, "WIPE" still distinct):

```swift
func testNewAndEndCopyDescribeArchivalNotErasure() {
    XCTAssertTrue(ConfirmationAction.newPatient.detail.lowercased().contains("archive"))
    XCTAssertTrue(ConfirmationAction.endCare.detail.lowercased().contains("archive"))
    XCTAssertTrue(ConfirmationAction.wipe.detail.lowercased().contains("purge"))
}
```

- [ ] **Step 4: Run GREEN + full suites** → new persistence tests pass; the updated `LifecycleAffordanceTests` passes; full app suite + full TCCCKit green. Resolve any call site that fails to compile from the async change.

- [ ] **Step 5: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add -A
git commit -m "feat(persistence): PRESERVE (archive) / PURGE (wipe) lifecycle wiring + copy"
```

---

## Task B7: Whole-branch review + device validation (no new code)

- [ ] Full TCCCKit suite green; full app suite green on the working destination.
- [ ] Whole-branch opus review of the B commit range: re-verify TCCCKit added no disk I/O; the engine restore reproduces state; LLM-never-mutates + `snapshot() == project(log)` still hold; continuous persistence + cursor has no double-write or loss path; manifest-desync trusts the log.
- [ ] **Device validation on iPhone 17 Pro** (simulator file-protection is weaker):
  - Build + run on device; capture an encounter; force-quit mid-care; relaunch → the in-progress casualty is recovered.
  - New Casualty → confirm the prior `events.jsonl` persists under `Documents/encounters/`.
  - WIPE (hold-3s) → confirm `encounters/` is gone.
  - Confirm written files report `NSFileProtectionComplete` (via a debug readback of `.fileProtectionKey`).
- [ ] Then superpowers:finishing-a-development-branch.

## Acceptance gate (sub-cycle B)

1. 752+ TCCCKit + 72+ app tests green at every boundary.
2. Continuous durability: an event is on disk before the next user action (B4 test).
3. Crash recovery: a fresh AppState reload reproduces the pre-crash projection (B5 test).
4. Corrupt-tail tolerance (B2 test).
5. PRESERVE: prior casualty file survives New Casualty (B6 test). PURGE: WIPE removes the tree + `!exists` (B6 test).
6. Encryption at rest asserted in tests; **device-validated** in B7.
7. Invariant intact (whole-branch review).
