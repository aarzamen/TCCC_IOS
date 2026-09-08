# Transcription Baseline — Apple SFSpeechRecognizer (current default lane)

> **Correction, 2026-09-08:** The historical measurements below are retained, but the attribution to recognizer long-form loss was incorrect. A protected physical-device callback trace shows Apple delivers eight timed utterances; our replace-only assembler drops all but the last. The recording also contains an extra scenario absent from the bundled reference, so its whole-file WER is not a matched accuracy measurement. See [speech coverage delivery](../superpowers/plans/2026-09-08-speech-coverage.md) for the fix and controlled comparison. These results alone do not justify a backend replacement.

**Date:** 2026-07-02
**Build:** `c0be70d` on `feat/phase01-stamp-bench` (build-identity stamp shipped this sprint)
**Device:** iPhone 17 Pro, iOS 26.2 (on-device recognition; `requiresOnDeviceRecognition = true`)
**Harness:** `--transcription-benchmark` DevTools runner, file-ingestion mode
(`SFSpeechURLRecognitionRequest`), scored by `TCCCBench` (WER / keyword recall /
extraction) — sprint WS-0 + WS-1.
**Fixture:** `valdez_alley` — authored GSW-left-thigh / tourniquet-conversion
scenario (`DevTools/Fixtures/valdez_alley.txt`, 323 reference tokens), rendered
to audio via Kokoro-TTS (see [[kokoro-ground-truth-workflow]]). Ground truth
confirmed to match the audio (the transcribed tail is the script's closing
lines, near-verbatim).

---

## Headline finding

**The current SFSpeechRecognizer lane does not support long-form dictation. On a
3.9-minute narration it returned only the final utterance (~52 words / the last
~40 seconds); the first ~3.3 minutes were never transcribed.**

This is the empirical justification for the sprint's move to the iOS 26
`SpeechAnalyzer` / `SpeechTranscriber` long-form API (WS-3). It is not a harness
bug and not a ground-truth mismatch — the harness worked end-to-end and caught
exactly the limitation it exists to surface. Decision (operator): record this as
the baseline result and address it in WS-3; do not add audio chunking to Phase 1.

## Numbers (matched-reference run, startedAt 2026-07-02T20:22:53Z)

| Metric | Value | Note |
|---|---|---|
| WER | **85.76%** | dominated by truncation, not word errors |
| — substitutions | 6 | in the transcribed tail (attempting→"emptying", packaged→"packed", MEDEVAC→"Meta", the→"TH a", …) |
| — insertions | 0 | |
| — deletions | **271 / 323** | the un-transcribed first ~3.3 min |
| Keyword recall | 23% (3/13) | hits: tourniquet, pressure dressing, urgent surgical — all in the tail |
| Extraction (DD-1380 fields) | 1/8 | only `tourniquet` intervention; vitals lost because the "Blood pressure is…" lead-ins were truncated |
| First-partial latency | 0.34 s | |
| Wall time | 9.3 s | to process the full 3.9-min file |
| Available-memory delta | ~0 MB (6133→6133) | Apple lane loads no in-process model (system-managed assets) — footprint probing is N/A for this lane |

### Transcribed output (evidence of truncation)
> "Is 100/65 oxygen saturation is 97% because TH a bleeding is controlled and we
> have time before evacuation I am emptying a tourniquet conversion to the
> pressure dressing wound stays dry the conversion is successful casualty is
> packed and ready for evacuation requesting urgent surgical Meta end of report"

This is the script's final paragraph only (the "Reassessment at ten fifteen…"
section). Everything before it — the 9-line request, casualty ID, massive-
hemorrhage/tourniquet, airway, respiration, and most of circulation — is absent.
Where the recognizer *did* transcribe, accuracy is high (6 substitutions across
~52 words); the failure mode is coverage, not word error.

## Interpretation

- **Truncation, not inaccuracy.** SFSpeechRecognizer is built for short
  utterances; on long audio its final `bestTranscription` reflects only the last
  segment. Confirmed independently earlier the same session on the prior
  (215 s) audio, which likewise returned only its tail.
- **Downstream extraction collapses with it.** The engine extracts poorly not
  because extraction is weak but because the vitals/interventions it needs were
  never transcribed. ASR coverage is the upstream bottleneck for the DD-1380
  deliverable.
- **A clean full-length word-accuracy baseline is not obtainable on this lane.**
  It belongs to WS-3 (SpeechAnalyzer, long-form-native) or, if a current-lane
  number is wanted sooner, a sub-60-second clip that fits one recognition window.

## Device-hardening fixed while establishing this baseline (commit `a569e7d`)

The first on-device runs surfaced three real issues (all fixed; the sim tests
never exercised the live path):
1. **SIGTRAP on launch** — `SFSpeechRecognizer.requestAuthorization` fired its
   completion handler more than once, double-resuming a `CheckedContinuation`.
   Fixed with a status short-circuit + a once-guarded continuation (`OnceFlag`).
2. **Zero results from buffer-feeding a file** — faster-than-real-time feeding of
   `SFSpeechAudioBufferRecognitionRequest` yields nothing. File mode switched to
   `SFSpeechURLRecognitionRequest` (shared config via `SpeechRequestFactory.configure`).
3. **No failure diagnostics** — added `results/_progress.txt` stage breadcrumbs +
   `_error.txt` + per-fixture try/catch, so a device failure is diagnosable from
   the container without a debugger. (This is how the truncation was localized.)

## Acoustic replay procedure (for the WS-2 capture-DSP A/B — mic-path runs)

The file-ingestion baseline above bypasses the mic/AGC pipeline. To A/B capture
DSP (Voice-Processing AGC vs `.measurement` + software conditioner), run the
same fixture through the real mic:

1. Quiet room. iPhone flat on desk, screen up, bottom edge (primary mic) facing
   the Mac speakers, ~50 cm away, Mac volume ~60%.
2. Launch the app normally (no benchmark arg). Start Live Capture. Play the
   fixture audio on the Mac (`afplay "<fixture>.m4a"`).
3. Stop capture ≥10 s after playback ends. Export/pull the transcript; score via
   the same `TCCCBench` reference.
4. Three runs per configuration arm; report per-run WER and the median. Tag
   results `mode: acoustic`. Only compare acoustic-to-acoustic.

Note: acoustic replay does not escape the long-form truncation — for a full-
length mic-path comparison, use short clips or the WS-3 SpeechAnalyzer lane.

## Follow-ups

- **WS-3 (primary):** SpeechAnalyzer/SpeechTranscriber lane — long-form native;
  re-run this exact fixture there for the real long-form numbers and A/B vs the
  customized dictation path.
- **Clean single-scenario fixture:** the current audio ("Seabee Golf Course")
  renders the authored script but may carry a second scenario as a preamble; a
  re-render of only the Reaper block gives a tidy fixture (non-blocking).
- **TokenNormalizer number forms (WS-1 polish):** does not yet fold "hundred" or
  "one ten"=110 compounds; low impact while truncation dominates, revisit when
  measuring real long-form output.
