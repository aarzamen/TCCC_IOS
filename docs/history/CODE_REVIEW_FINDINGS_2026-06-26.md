# Code Review Findings — Transcription Finalization + Harness — 2026-06-26

**What ran:** a local multi-agent code review (the `/code-review` recipe — finder
angles → per-finding verification → gap sweep → ≤15 ranked findings), executed as a
Workflow in-session over two targets: the streaming-ASR tentative→permanent commit
pipeline (the freshly-built finalize-only change `b32fffc`) and the LLM-never-mutates
harness invariants. 6 lenses, 42 subagents.

**Verdict:** the finalize-only change (`b32fffc`) traded a **cosmetic** duplication for
multiple **silent data-loss** paths — the wrong trade for a casualty-care record.
**Reverted in `76a5903`.** 11 CONFIRMED + 4 PLAUSIBLE findings below.

The duplication itself is clinically harmless: the engine's extractors are idempotent
(a device export showed 7 distinct interventions, not 14). So the correct posture is
**loss-safe first** (snapshot-commit), then fix duplication *without* sacrificing
loss-safety.

---

## A. Resolved by the revert (finalize-only loss paths)

These exist only because finalize-only made the `isFinal` echo the *sole* commit. The
revert restores the snapshot-commit (commit the on-screen text first), so a failed/late
echo no longer loses anything.

| # | File:line | Loss path |
|---|---|---|
| 1, 7, 10 | SpeechRecognizer.swift:222 / LiveCaptureScreen.swift:737,743 | `forceFinalize`→`endAudio` returns an **error/empty** → no isFinal echo → the ~8 s chunk is dropped **and recognition dies for the rest of the recording**, `isRecording` still true, no error surfaced. |
| 2 | LiveCaptureScreen.swift:600 (STOP) | Task-ordering race: `handleFinalResult` can run before `emit`, finishing the continuation → the final in-flight line (e.g. a drug/dose) is dropped. |
| 8 | LiveCaptureScreen.swift:733 (30 s tail) | `forceFinalize` is a no-op during the tail (`tailDeadline != nil`), so trailing speech — the tail's whole purpose — never commits and is lost at teardown. |
| 3 | SpeechRecognizer.swift:250 | `forceFinalize` is a no-op if the recognizer was torn down between scheduling and the await → chunk lost. |
| 5 | LiveCaptureScreen.swift:151 (off-screen/background) | watchdog runs off-screen; a finalize error loses the chunk with the only signal on a StatusStrip badge the operator isn't looking at. |
| 6 | LiveCaptureScreen.swift:731 (**Parakeet**) | `forceFinalize()` is a **no-op default** for Parakeet, so finalize-only made the watchdog + debounce commit **nothing** — it broke that backend's safety net entirely. |
| 15 | LiveCaptureScreen.swift:745 | `lastCommitAt` was stamped *before* the await, so a failed finalize still deferred the watchdog 8 s. (Post-revert the stamp follows a successful snapshot commit.) |

---

## B. Still open after the revert (pre-existing / restored — fix in the redesign)

| # | File:line | Issue | Severity |
|---|---|---|---|
| 9, 13 | AppState.swift:492 | **SUPERSET (`hasPrefix`) dedup false-positive** — a legitimately restated utterance that begins with the previous committed line ("Tourniquet applied" → "Tourniquet applied high and tight time 0930") gets truncated to just the tail, so the engine loses the anchor words. Heuristic has no echo-identity/time window. | CONFIRMED / PLAUSIBLE |
| 11 | LiveCaptureScreen.swift:167 | **Interruption-pause loses the in-flight partial** — the pause handler (`pendingInterruptionPause`) calls `stopImmediate()` without finalizing/committing first, so a mid-sentence fragment during a phone call / Siri / alarm is dropped. Asymmetric with STOP (which finalizes first) and with the memory-pressure handler (which snapshot-commits). | CONFIRMED |
| 4 | AppState.swift:237 | The **memory-pressure** handler snapshot-commits without finalizing → duplicate when the revised echo lands. Part of the general cosmetic-dup problem; consistent with the rest post-revert. | CONFIRMED |
| 14 | AppState.swift:488 | **EXACT dedup** has no time/identity window — two *immediately consecutive* identical lines (a back-to-back bilateral restate) drop the second. Narrow trigger. | PLAUSIBLE |
| 12 | LiveCaptureScreen.swift:746 | On Parakeet the debounce/watchdog give zero benefit (no-op `forceFinalize`); commits wait for Parakeet's own EOU/ceiling/stop. **Delay**, not loss. Post-revert the snapshot commit fixes it. | PLAUSIBLE |

---

## C. The deferred redesign — "duplication done right" (loss-safe AND dedup-correct)

The cosmetic duplication is back (snapshot line + revised `isFinal` echo, where Apple
Speech rewrites earlier words — "high-end" → "high and tight" — defeating exact/prefix
dedup). The correct fix keeps loss-safety:

1. **Commit the snapshot immediately** (loss-safe), but mark it *provisional* and record
   its line id + the time.
2. **When the refined `isFinal` echo arrives** for that same chunk (within a short
   window), **replace** the provisional line in place (and re-key its engine evidence)
   rather than appending a second line — instead of relying on a lexical dedup that can
   neither catch a word-revision nor safely truncate a coincidental prefix.
3. Drop the brittle `hasPrefix` SUPERSET heuristic (finding #9/#13) in favor of the
   provisional-replace mechanism, which is identity-scoped (no false positives).
4. Fix the **interruption-pause** path (#11) to finalize/commit the partial first, like
   STOP does.
5. Give the EXACT dedup (#14) a short time window so only true back-to-back echoes are
   swallowed.

Target backends: Apple Speech (primary), Parakeet (no-op `forceFinalize` — the snapshot
commit is the real commit there), Granite (Codex's lane, separate).
