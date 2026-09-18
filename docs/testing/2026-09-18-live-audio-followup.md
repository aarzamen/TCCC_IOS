# Live audio and casualty-number follow-up — 18 September 2026

The operator tested the installed automatic-gain build using the requested
fictional vital-sign phrase at two volumes, then reported that New Casualty
reused C-05. The new recording and matching encounter artifacts were inspected
locally. Recordings, raw transcripts, device identifiers and full manifests
remain private and are not included here.

## Findings and corrections

1. **Casualty numbering restarted after app relaunch.** Recovery restored the
   displayed label but left its counter at the initial value. Allocation now
   consults the maximum numeric label in active and archived encounters. The
   recovered encounter retains its original label; only the next new casualty
   advances. Unreadable numbering history blocks allocation before current care
   is cleared. Old records are not renumbered or rewritten.
2. **Periodic recognition rotation could cut a spoken number.** The eight-second
   UI watchdog ended Apple recognition immediately, even while speech continued.
   In the synthetic read-aloud, a separated number prefix reached extraction as
   a completed pulse value. Rotation now requests a boundary rather than
   assuming one: current quiet PCM and a stable hypothesis must agree. Bounded
   forced rotation retains an incomplete segment for review and continues the
   capture; it cannot treat an arbitrary cut as a clinical final. No numeric
   fragments are guessed or concatenated into a new value. Successors also stay
   review-only until a verified safe boundary, so a detached negation cannot
   become an affirmative finding. The fixed post-roll deadline uses the same
   classification when speech is still in progress.
3. **Blood pressure created false hemorrhage evidence.** The inherited keyword
   matcher treated the word “blood” in “blood pressure” as positive bleeding and
   as hemorrhage location context. The blood-pressure phrase is now excluded
   from those evidence checks. Explicit bleeding, including bleeding mentioned
   in the same sentence as a pressure reading, remains recognized.

The AAC archive decoded successfully and showed no full-scale clipping. That
supports the recording path, not a claim of complete transcription accuracy.
The live transcript/extraction test did expose the errors above and is not
recorded as a pass. Existing test-encounter values are preserved as evidence;
this source correction does not silently rewrite their history.

## Verification

- Full TCCCKit suite: **918 tests passed**, zero failures.
- Focused iOS app integration suite: **136 tests passed**, zero failures,
  covering numbering recovery, recognition boundaries and lifecycle, archive
  conversion, backend provenance, wireless resume and documentation wiring.
- Regression failures were demonstrated before the fixes. The new coverage
  includes repeated relaunch, archived higher labels, corrupt history, speech
  crossing the old timer boundary, successors of unsafe cuts, and blood-pressure
  sentences with and without explicit bleeding.
- Independent source review identified and verified the successor quarantine
  correction; no further actionable findings remained in that review.

Boundary tuning is conservative: one second of continuous quiet PCM, a
hypothesis stable for 2.5 seconds, and fresh audio are required for requested
rotation. At 55 seconds of supplied audio, an unsafe request is retained for
review. These thresholds passed deterministic regressions; a fresh on-device
read-aloud is still needed to measure acoustic behavior in the operator's room.

Signed device build and in-place update are pending.

Native Claude Code contributed a scoped, source-only partial implementation of
the numbering correction. It reached its turn limit; Codex completed, reviewed
and tested the integrated change. Claude received no recordings or device data.
