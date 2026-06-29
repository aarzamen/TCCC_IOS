# Design — ASR Provisional-Replace Commit Pipeline — 2026-06-28

## Context

The streaming-ASR tentative→permanent commit pipeline currently de-dupes the
`forceFinalize()` echo with a lexical heuristic in `AppState.appendFinal`
(EXACT match + `hasPrefix` SUPERSET truncation). The 2026-06-26 multi-agent
code review (`CODE_REVIEW_FINDINGS_2026-06-26.md`) found that heuristic both
lossy and false-positive-prone, and recommended a **loss-safe-first
provisional-replace** redesign (its Section C). This spec is that redesign,
built against the post-consolidation `main` (`0d77d1a`).

The review's loss paths in its Section A are already closed by the
finalize-only revert (`76a5903`, in `main`). This spec addresses the
**still-open** Section B/C findings: #2, #4, #6, #8, #9, #11, #12, #13, #14.

A parked work-in-progress (`PartialCommitGate`, currently uncommitted in the
Codex worktree `~/.codex/worktrees/f230`) is **absorbed** by this design, not
discarded — see "Relationship to the Codex WIP" below.

## Goals

1. **Loss-safe first.** A committed utterance is never lost to a failed, late,
   or absent `isFinal` echo. The on-screen commit happens immediately.
2. **Correct refinement.** When the recognizer revises words
   (`"high-end"` → `"high and tight"`, a misheard drug/dose, a corrected
   number), the **refined words win** in both the transcript *and* the
   structured engine state.
3. **No cosmetic duplication.** The snapshot line and its refined echo render
   as one line, not two.
4. **Identity-scoped, not lexical.** Dedup decisions are made by chunk identity
   (position in the commit stream), eliminating the lexical false positives of
   findings #9/#13/#14.

## Non-goals

- Changing the ASR backends themselves (Apple Speech, Parakeet, Granite).
- The Granite lane (Codex's) — untouched.
- Multi-casualty UI, or any engine extractor behavior change. Extractors run
  exactly as today; only *when* and *against what baseline* changes.

## Two decisions that frame the design

- **Absorb the Codex `PartialCommitGate`** (commit-trigger guard) AND add
  provisional-replace (append/replace layer). Two complementary layers.
- **Refined words win** — engine state is superseded to reflect refined text,
  via in-memory log-tail rollback (not a fold rewrite).

## Architecture — two layers

### Layer 1 — Commit-trigger guard (app: `LiveCaptureScreen`)

Codex's `PartialCommitGate.committableText(scheduled:latest:)` decides *whether*
the silence-debounce / watchdog fires a commit. It commits the scheduled text
only when that text is still a stable **prefix at a token boundary** of the
latest partial, and **refuses** when the recognizer is actively rewriting the
prefix (`"Trepanation…"` → `"Respiration…"`). Lifted in from the WIP as-is,
with its tests.

### Layer 2 — Provisional-replace (app: `AppState` + engine: `TCCCKit`)

A committed chunk is **provisional** until it settles. The core invariant:

> **At most one provisional chunk is outstanding at a time.** The next chunk
> cannot commit until the current one settles. Therefore a provisional chunk's
> events are always the **tail** of the encounter log.

#### Chunk lifecycle

```
 debounce/watchdog fires ─▶ COMMIT (provisional)
      • append transcript line          (loss-safe, on screen now)
      • engine runs on provisional text  (live facts)
      • line marked provisional; 2.0s settle-window timer starts
      │
      ├─ first isFinal echo within window ─▶ REPLACE
      │        • swap line text in place
      │        • engine: roll back + re-run on refined text
      │        • settle
      │
      ├─ window expires (no echo)        ─▶ SETTLE (timeout): promote as-is
      │
      └─ STOP / interruption / next chunk ─▶ SETTLE (succession): promote first,
                                              then proceed
```

Three terminal outcomes: **replaced**, **settled-by-timeout**,
**settled-by-succession**. All three are loss-safe — the transcript line is on
screen from the moment of COMMIT.

## Engine supersession — log-tail rollback (the `TCCCKit` change)

Naïve supersession fails because the engine is incremental: `processTranscript`
emits `deterministicFact` events as **deltas** against current state, and
`project(log)` **replays recorded deltas** — it does not re-extract from text.
Running the engine on refined text would emit a delta relative to the
*provisional* state we are trying to undo.

The single-provisional invariant makes the provisional chunk the **log tail**,
which turns supersession into truncate-and-reapply:

```
COMMIT (provisional "TQ applied high end"):
    preState = patients            // snapshot before this chunk
    cursor   = log.count           // tail boundary
    processTranscript("TQ applied high end")
        → log += [asrSegment#k, deterministicFact(Δ vs preState)]

REPLACE (refined "TQ applied high and tight"):
    patients = preState            // roll back in memory
    log.truncate(to: cursor)       // drop this chunk's facts (it is the tail)
    // retain asrSegment#k as a flagged retired-generation audit event
    processTranscript("TQ applied high and tight")
        → log += [asrSegment#k', deterministicFact(Δ' vs preState)]  // correct baseline
```

Because `patients` is reset to `preState` and the log truncated to `cursor`
*before* re-running, the refined delta is computed against the correct
baseline. The post-replace state is byte-identical to a world where only the
refined text was ever processed — so the existing `LogEquivalenceTests`
(`snapshot() == project(log)`) gate the change for free.

### New engine API (TCCCKit, `@MainActor`-guarded like existing mutators)

```swift
func reviseProvisionalTail(
    to cursor: Int,
    preState: [String: PatientState],
    refinedText: String,
    timestamp: Date
)
```

- Asserts `cursor` is still the log tail (defends the invariant; traps if not).
- Restores `preState`, truncates the log to `cursor`, retains the superseded
  `asrSegment` as a flagged audit event, then re-runs extraction on
  `refinedText`.
- The engine remains the sole writer of `PatientState`. `AppState` owns
  `preState` + `cursor` for the outstanding provisional chunk.

### Audit trail

The originally-heard `asrSegment` is **retained**, flagged as a retired
generation. The log records "heard X, corrected to Y" — medico-legal value for
a casualty card. `asrSegment` events are ignored by state projection
(`PatientStateProjection`), so retaining them cannot corrupt state.

## Persistence + crash recovery

The on-disk log is append-only JSONL — a flushed line cannot be truncated. So:

> **A provisional chunk's events are not flushed to disk until it settles.**

The cursor-guarded `persistNewEvents` (the BLOCK A coalescing serialize guard)
flushes only *up to* the provisional boundary. On settle:

- **Replaced** → gen-0 facts were never on disk, so the in-memory truncate is
  invisible to disk. Flush the retired `asrSegment#k` (audit) + refined
  `asrSegment#k'` + refined facts together.
- **Timeout / succession** → flush the provisional generation as-is.

Disk therefore only ever sees *settled* generations; `project(restore)` stays
correct with **no supersede marker on disk**.

**Crash exposure:** the settle window is 2.0s, so a crash can lose at most the
single in-flight chunk's transcript line. The audio recording captures and
persists continuously, so the raw audio of those ≤2s survives regardless. All
settled chunks' facts are already on disk. Strictly safer than today.

## Matching, backends, and lifecycle edges

**Matching** — identity by position. The COMMIT calls `forceFinalize()`, which
resets the recognizer's recognition context; the recognizer's **first
`isFinal` after a provisional commit, within the window, is that chunk's
refinement**. No lexical matching. Refined text wins; absent echo → timeout
settle.

**`isFinal` with no outstanding provisional** — a spontaneous endpoint
`isFinal` (Apple Speech finalizing at a natural pause, with no debounce COMMIT
ahead of it) commits a fresh chunk that **settles immediately**: it is already
final, so no refinement is expected and no window is opened. This is the only
path that does not pass through the 2.0s window.

**Deletion** — the entire EXACT + SUPERSET dedup block in `appendFinal`
(current lines 487–498) is **removed**. Replace intercepts the echo before it
can become a second line, so the lexical heuristic is unnecessary. This is the
identity-scoped mechanism the review's step 3 asks for, and it dissolves
findings #9/#13 (anchor-word truncation) and #14 (un-windowed exact dedup).

**All backends fall out of one model:**

| Backend / path | Behavior | Finding closed |
|---|---|---|
| Apple Speech | echo arrives → replace with refined text | #9/#13 |
| Parakeet (`forceFinalize` no-op) | no echo → settle by timeout; snapshot **is** the commit | #6, #12 |
| 30s tail (`forceFinalize` no-op during tail) | settle by timeout → trailing speech preserved | #8 |

**Lifecycle edges:**

- **STOP** → promote outstanding provisional first (loss-safe), then teardown.
  Closes the #2 ordering race.
- **Interruption-pause (#11)** → currently calls `stopImmediate()` with no
  flush. Fix: promote the outstanding provisional + flush the partial first,
  symmetric with STOP.
- **Memory-pressure (#4)** → already snapshot-commits; now simply promotes the
  provisional — consistent, no special-case duplicate.

## Components changed

- **`TCCC_IOS/App/AppState.swift`** — provisional-chunk state (`preState`,
  `cursor`, line id, window timer); COMMIT / REPLACE / SETTLE transitions;
  removal of the lexical dedup block in `appendFinal`; lifecycle promote-first.
- **`TCCC_IOS/App/PartialCommitGate.swift`** — lifted from Codex WIP verbatim.
- **`TCCC_IOS/Screens/LiveCaptureScreen.swift`** — debounce/watchdog use
  `PartialCommitGate`; interruption-pause promote+flush; STOP promote-first.
- **`Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift`** —
  `reviseProvisionalTail(...)`; log-tail truncate; retired-asrSegment audit
  flag. `project(log)` semantics unchanged.
- **`TCCC_IOS.xcodeproj/project.pbxproj`** — regenerated via `xcodegen` for new
  files.

## Testing strategy (TDD)

**TCCCKit (core):**
- Extend `LogEquivalenceTests`: commit→revise→assert `snapshot()==project(log)`;
  commit→revise→commit-next; revise-to-fewer-facts; revise-to-more-facts.
- Correctness oracle: `commit("TQ applied high end") → revise("TQ applied high
  and tight")` yields `PatientState` identical to a fresh engine that only
  processed `"high and tight"`.
- Audit: retired `asrSegment` retained + flagged; state identical with/without
  it present.
- Tail invariant: `reviseProvisionalTail` traps when `cursor` is not the tail.

**App layer:**
- Port `PartialCommitGateTests` verbatim from the Codex WIP.
- Provisional lifecycle: commit→replace (one line, text swapped);
  commit→timeout-settle; commit→succession-settle.
- Each finding → a named regression test: #2 STOP keeps last in-flight line;
  #4 memory-pressure no dup; #6/#12 Parakeet settles by timeout; #8 tail
  preserves trailing speech; #9/#13 restate keeps anchor words; #11
  interruption promote+flush; #14 two identical back-to-back utterances both
  survive.
- Port Codex's run-on/unpunctuated `PatientStateEngineTests` case.

**Verification gate:** `swift test` (TCCCKit) + app test bundle + a device
smoke test (continuous narration → no dup lines, facts correct, audio intact)
before merge to `main`.

## Relationship to the Codex WIP

The parked `~/.codex/worktrees/f230` WIP is **absorbed**:
- `PartialCommitGate` + its tests are lifted in verbatim (Layer 1).
- Codex's `nonOverlappingFinalText` lexical tail-truncation in `appendFinal`
  is **superseded** by this design's identity-scoped replace (it shared the
  hasPrefix philosophy the review flags as #9/#13) — not carried over.
- Codex's run-on extraction test is carried in.

Once this lands, the f230 worktree's remaining uncommitted delta is fully
represented (or intentionally superseded) and can be retired.

## Tunables

- `settleWindow = 2.0s` — how long to await the refined echo before
  timeout-settle. Named constant alongside `silenceDebounce` (1.5s); field-
  tunable.

## Out of scope / deferred

- Engine-on-partial-text (extracting before COMMIT) — separate future-work item.
- Adaptive debounce/window tuning — field data first.
- Granite lane integration — Codex's.
