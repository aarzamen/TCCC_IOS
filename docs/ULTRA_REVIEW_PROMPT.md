# Ultra Review Prompt — 2026-06-26

Paste the block below as the focus for `/code-review ultra`. It targets the two
transitions worth a deep, billed pass: the LLM-as-agentic-harness reframe
(event-sourcing core + BLOCK A incremental projection, already on `main`) and the
streaming-ASR tentative→permanent transcription path (the continuous-speech
finalization fix landed this session).

Context for the reviewer: a device session on the iPhone 17 Pro proved that a
4-minute continuous narration transcribed correctly on screen but **never
committed** — `EXTRACTED` stayed 0 and the on-disk `events.jsonl` held only the
seed event — because on-device Apple Speech never emits its own `isFinal` and the
sole commit trigger was a 2.5 s silence debounce that continuous speech never
satisfies. The fix adds a watchdog that finalizes the in-flight pass every ~8 s, a
flush-on-stop, and a shared `commitPartial` path. A device re-test confirmed the
loss bug is fixed (full MARCH-PAWS extraction from a continuous read) but exposed a
duplication: committing the on-screen snapshot AND the `forceFinalize` echo produced
two near-duplicate lines per chunk, because on-device Apple Speech *revises* earlier
words when it finalizes ("high-end" → "high and tight"), defeating exact/prefix
dedup. That is now fixed at the source: **`commitPartial` is finalize-only** — it no
longer commits the rough snapshot; the authoritative `isFinal` echo is the sole
commit per chunk. `AppState.appendFinal` retains an exact/superset dedup as a
defensive backstop. Please verify the finalize-only path is lossless and exactly-once
and that the backstop dedup can't wrongly drop a legitimate line.

---

```
Focus this review on two transitions — not the whole codebase.

1. LLM-AS-AGENTIC-HARNESS (not LLM-with-tricks).
This app was reframed so the on-device LLM is a *proposer* inside an
event-sourced harness, never a direct mutator of clinical state. Verify it
holds structurally:
- PatientState is a pure projection of an append-only EncounterEvent log
  (PatientStateEngine.project(log)); the engine is the SOLE writer of state.
- The LLM reaches state ONLY via operator-accepted facts → FieldRouter →
  typed PatientStateFieldWrite → applyWrite. No path lets free-form LLM
  output mutate PatientState directly.
- The recent incremental-projection change (materialized `patients` dict
  replacing per-call project(log)) must stay provably equal to the full
  re-fold, and project(log) must remain the restore/replay authority.
- Hunt for leaks: an LLM string reaching a setter, a validator bypassed,
  the log not canonical, or live state diverging from project(log).

2. TENTATIVE → PERMANENT TRANSCRIPTION.
The point where streaming ASR partials become committed, engine-extracted,
persisted documentation. A continuous-speech finalization bug was just fixed
in LiveCaptureScreen (a watchdog finalizes the in-flight pass every ~8s + a
flush-on-stop + a shared commitPartial path), because on-device Apple Speech
never fires isFinal and the 2.5s silence debounce alone lost unbroken
narration. commitPartial is now FINALIZE-ONLY: it does not commit the rough
on-screen snapshot; it calls forceFinalize() and the authoritative isFinal
echo is the sole commit per chunk (the snapshot+echo pair was producing
near-duplicate lines because the final pass revises earlier words). Verify:
- The tentative→final transition is lossless and exactly-once under BOTH
  continuous speech and natural pauses, with NO duplicate/overlapping lines.
- Finalize-only soundness: if a forceFinalize pass yields no isFinal (error /
  empty), is that chunk silently lost? How likely, how bad, and is the watchdog
  redundancy enough? (The prior snapshot-commit was the fallback that's now gone.)
- The retained exact/superset dedup in AppState.appendFinal is now a backstop —
  confirm it can't wrongly drop a legitimate line (e.g. a real repeated prefix).
- Task lifecycle: the watchdog (periodicCommitTask) is cancelled on every
  teardown path — no leak, no commit into a torn-down recognizer.
- The tail/stop interaction (forceFinalize is a no-op during the tail)
  loses or duplicates no trailing speech.

Out of scope: UI styling, the Granite Speech ASR lane (separate known WIP),
unrelated subsystems.
```
