# Engine Incremental Projection (BLOCK A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the engine's projection incremental — stop re-folding the whole event log on every transcript line / operator accept, and stop deep-copying the whole `EncounterLog` on every persist — with **zero observable behavior change**.

**Architecture:** The imperative extractor loop already maintains `patients`; remove the redundant `patients = project(log)` re-fold (and apply operator accepts in place). `project(log)` stays the pure full-fold used by `restore` + as the equivalence oracle. Persistence reads only the new-events slice instead of the whole log.

**Tech Stack:** Swift 6 actor (`PatientStateEngine`), XCTest. No new types, no public-API breakage.

**Spec:** `docs/superpowers/specs/2026-06-25-engine-incremental-projection-design.md`.

## Global Constraints

- **Zero behavior change.** `snapshot() == project(log)` MUST hold — the existing `LogEquivalenceTests` (`project(snapshotLog()) == snapshot()` over the 4 fixtures + multi-chunk) are the gate; if any goes red, the materialized view diverged.
- **755 TCCCKit + 84 app tests green at every task boundary.**
- **`project(log)` is untouched** (the full re-fold) — it remains the `restore`/replay-on-launch authority and the equivalence oracle. Only the *live mutation path* stops calling it.
- **LLM-never-mutates-state unchanged** — operator facts still flow `OperatorAcceptedFact` → `FieldRouter` → `PatientStateFieldWrite` → `applyWrite`.
- `newEvents(since:)` is additive; `snapshot()`/`snapshot(of:)`/`snapshotLog()`/`project` signatures are unchanged.

**Build / verify**
- TCCCKit (Task 1, Task 2-engine): `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`
- App (Task 2-app): `cd /Users/ama/TCCC_IOS && xcodegen generate && xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' -configuration Debug CODE_SIGNING_ALLOWED=NO -skipMacroValidation -only-testing:TCCC_IOSTests`
  - bare `id=`/`generic/platform=` FAIL; class-level `-only-testing:Target/Class` reports 0 — use the full target. No new app FILES here, so the pbxproj should be unchanged (run `xcodegen generate` anyway; `git add` it only if it changed).

---

## File Structure

**Modified (TCCCKit):**
- `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` — remove the re-fold in `processTranscript` (T1) + `recordOperatorAcceptedFact` (T1); add `newEvents(since:)` (T2).
- `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift` — divergence stress test (T1) + `newEvents` slice test (T2).

**Modified (app):**
- `TCCC_IOS/App/AppState.swift` — `persistNewEvents()` uses `newEvents(since:)` (T2).

---

## Task 1: Incremental projection — drop the per-call re-fold (TCCCKit)

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (`processTranscript:128`, `recordOperatorAcceptedFact:172`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift` (add)

**Interfaces:** No signature changes. `snapshot()` now returns the incrementally-maintained materialized view (provably equal to `project(log)`).

- [ ] **Step 1: Write the regression-lock test** (append to `LogEquivalenceTests.swift`)

This is an optimization (identical output), so the test LOCKS behavior rather than RED→GREEN: it must pass **before** the change (current full re-fold) and stay green **after** (incremental). It interleaves transcript + operator accepts — the operator-accept path is not covered by the transcript-only fixtures.

```swift
func testIncrementalProjectionNeverDivergesAcrossTranscriptAndAccepts() async throws {
    let engine = PatientStateEngine.standard()
    await engine.processTranscript("GSW right thigh. Heart rate one ten.")
    await engine.recordOperatorAcceptedFact(
        write: .spo2(94), factId: "g1", domain: "vitals", field: "spo2",
        rawValue: "94", to: "PATIENT_1")
    await engine.processTranscript("Blood pressure ninety over sixty. Tourniquet applied.")
    await engine.recordOperatorAcceptedFact(
        write: .pain("ketamine"), factId: "g2", domain: "paws", field: "pain",
        rawValue: "ketamine", to: "PATIENT_1")
    await engine.processTranscript("Patient is alert.")

    // The incrementally-maintained snapshot must equal a fresh full re-fold of the log.
    let snap = await engine.snapshot()
    let projected = PatientStateEngine.project(await engine.snapshotLog())
    XCTAssertEqual(snap, projected,
                  "incremental materialized view must never diverge from project(log)")
    // …and the accepted writes actually landed through the incremental path:
    XCTAssertEqual(snap["PATIENT_1"]?.vitals.spo2, 94)
    XCTAssertEqual(snap["PATIENT_1"]?.paws.pain, "ketamine")
}
```

- [ ] **Step 2: Run it to confirm it passes PRE-change (locks current behavior)**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter LogEquivalenceTests`
Expected: PASS (current `patients = project(log)` makes `snapshot() == project(log)` trivially). This proves the test is a valid lock before we optimize.

- [ ] **Step 3: Make the change — remove both re-folds**

In `processTranscript`, delete the final re-fold (line ~128), leaving the imperatively-maintained `patients`:

```swift
        emitEvents(text: text, before: before, timestamp: unixTimestamp)
        // No re-fold: the imperative loop above already maintains `patients` as the
        // materialized projection. project(log) (used by restore + the equivalence
        // tests) is provably equal to it (A2 inverse property + A3 equivalence), so
        // recomputing it here would be O(N) wasted work per transcript line.
    }
```

In `recordOperatorAcceptedFact`, replace the `patients = Self.project(log)` line (~172) with an in-place apply that matches `project`'s `operatorAcceptedFact` handling exactly:

```swift
        opCount += 1
        log.append(.operatorAcceptedFact(.init(
            id: "op-\(opCount)", patientId: patientId, timestampUnix: unix,
            write: write, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
        // Incremental: apply the accepted write in place (identical to project()'s
        // operatorAcceptedFact arm) instead of re-folding the whole log.
        var p = patients[patientId]!          // ensurePatientExists guaranteed the row
        Self.applyWrite(write, to: &p)
        p.timestampLastUpdate = unix          // == the event's timestampUnix, as project sets it
        patients[patientId] = p
    }
```

- [ ] **Step 4: Run the full TCCCKit suite — the equivalence tests are the gate**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`
Expected: **all green** (was 755; +1 new = 756). The four scenario equivalence tests + `testAfterFlipSnapshotIsTheProjection` + the new stress test all asserting `snapshot() == project(log)` is the proof the materialized view never diverged. **If any equivalence test goes red, STOP** — the imperative path diverges from `project(log)` somewhere; do not weaken the test.

- [ ] **Step 5: Commit**

```bash
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
git commit -m "perf(engine): drop O(N) full-log re-fold per transcript line / accept (incremental materialized view)"
```

---

## Task 2: Slice accessor for persistence — stop copying the whole log (TCCCKit + app)

**Files:**
- Modify: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift` (add `newEvents(since:)`)
- Modify: `TCCC_IOS/App/AppState.swift` (`persistNewEvents()`)
- Test: `Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift` (add `newEvents` slice test)

**Interfaces:**
- Produces: `public func newEvents(since index: Int) -> [EncounterEvent]`. Consumed by `AppState.persistNewEvents`.

- [ ] **Step 1: Write the failing test** (append to `LogEquivalenceTests.swift`)

```swift
func testNewEventsSinceReturnsSuffixOrEmpty() async throws {
    let engine = PatientStateEngine.standard()
    await engine.processTranscript("Heart rate one ten.")
    let total = await engine.snapshotLog().events.count
    XCTAssertGreaterThan(total, 1)                      // seed + asr + facts
    XCTAssertEqual(await engine.newEvents(since: 0).count, total)        // whole log
    let tail = await engine.newEvents(since: total - 1)
    XCTAssertEqual(tail.count, 1)                                        // just the last event
    XCTAssertTrue(await engine.newEvents(since: total).isEmpty)         // caught up
    XCTAssertTrue(await engine.newEvents(since: total + 5).isEmpty)     // out-of-range guarded
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit --filter LogEquivalenceTests`
Expected: FAIL — `value of type 'PatientStateEngine' has no member 'newEvents'`.

- [ ] **Step 3: Implement the accessor** (add to `PatientStateEngine.swift`, near `snapshotLog`)

```swift
/// Events appended since `index` — a small slice copy, for incremental persistence
/// without deep-copying the entire `EncounterLog` struct. `index` is a count cursor;
/// out-of-range yields `[]`.
public func newEvents(since index: Int) -> [EncounterEvent] {
    guard index < log.events.count else { return [] }
    return Array(log.events[index...])
}
```

- [ ] **Step 4: Run GREEN (TCCCKit)**

Run: `swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit` → all green (757).

- [ ] **Step 5: Point `persistNewEvents` at the slice accessor** (`AppState.swift:554-565`)

```swift
    func persistNewEvents() async {
        guard let store = encounterStore else { return }
        let new = await engine.newEvents(since: persistedCursor)
        guard !new.isEmpty else { return }
        do {
            try await store.appendToActive(new)
            persistedCursor += new.count
        } catch {
            appendSystem("PERSIST FAILED · \(error.localizedDescription)")
        }
    }
```

> `persistedCursor += new.count` is equivalent to the old `persistedCursor = log.events.count` (new starts at the cursor and runs to the end), but avoids reading `log.events.count` via a whole-log copy.

- [ ] **Step 6: Run the app suite — persistence behavior must be unchanged**

Run the full app target (build cmd above). Expected: **84 green** (2 pre-existing skips). The B4/B5 persistence tests (`testTranscriptEventsArePersistedContinuously`, `testCrashRecoveryReplaysInProgressEncounter`, the lifecycle PRESERVE/PURGE tests) are the proof the slice path persists exactly the same events as before.

- [ ] **Step 7: Commit**

```bash
cd /Users/ama/TCCC_IOS && xcodegen generate
git add Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift TCCC_IOS/App/AppState.swift Packages/TCCCKit/Tests/TCCCExtractorTests/LogEquivalenceTests.swift
# include project.pbxproj only if `git status` shows it changed (no new files expected)
git commit -m "perf(persistence): persist via newEvents(since:) slice — no whole-EncounterLog copy per flush"
```

---

## Final verification (before whole-branch review)

- [ ] Full TCCCKit suite green (`swift test --package-path /Users/ama/TCCC_IOS/Packages/TCCCKit`) — ~757.
- [ ] Full app suite green on the working destination — 84.
- [ ] Acceptance gate (spec §7): every `LogEquivalenceTests` assertion (`snapshot() == project(log)`) green = the materialized view never diverged; the new stress + slice tests green; persistence tests green.
- [ ] Whole-branch opus review: re-verify (a) the imperative materialized view is provably equal to `project(log)` and can't silently diverge, (b) `project(log)` is still the `restore` authority, (c) LLM-never-mutates intact, (d) the persist slice yields identical on-disk results.
- [ ] superpowers:finishing-a-development-branch (merge locally on the user's say-so).
