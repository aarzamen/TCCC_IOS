# Speech coverage implementation plan

**Goal:** Preserve every utterance Apple delivers within one recognition request, while keeping partial revisions and request-final clinical extraction correct.

**Authority:** PROJECT_POLICY.md; user authorizes this debugging sprint and routine integration. Codex leads and verifies; native Claude implements the shared helper and its regression tests. Use systematic-debugging, test-driven-development and subagent-driven-development with one integration review.

**Evidence/design:** The physical iOS 26.2 callback trace contains eight non-final metadata-bearing utterances, each followed by fresh untimed partials; the terminal callback is empty. Replace-only assembly discards all earlier utterances. Speech metadata supplies request-relative start/duration. Preserve completed timed utterances, replace current provisional text, and avoid lexical deduplication. Keep request IDs, cancellation, operator authority and complete file protection unchanged. Do not switch recognition backends for this app-side defect.

## Delivery

- [x] Trace the existing file request on the physical iPhone; keep raw diagnostics private.
- [x] Native Claude: SpeechUtteranceAssembler.swift and SpeechUtteranceAssemblerTests.swift; verify failed retention assertion before implementing, then pass the focused Swift helper suite.
- [x] Codex: feed timing into the helper from AppleSpeechFileTranscriber/SpeechFileRunState and SpeechRecognizer; reset at request boundaries; preserve empty-final and incomplete outcomes. Add integrated run-state regressions.
- [x] Regenerate Xcode project, run focused/new tests and app integration suite, build/install on iPhone and compare original plus matched synthetic fixture before/after.
- [x] One integration review; correct concrete findings.
- [ ] Publish source/docs and install the merged build.

## Benchmark integrity

The original recording includes an additional scenario that its 323-token reference omits. Retain it untouched for callback-loss comparison, but do not report its full-file WER as a matched accuracy measurement. Add a separate local Samantha-voice recording rendered from the exact existing valdez_alley.txt reference at 145 words/minute (134.381 seconds). Keep recordings and raw traces out of the public repository. The file benchmark does not establish live-microphone acoustic performance.

## Verified results — 2026-09-08

Native Claude Code 2.1.197 at `/opt/homebrew/bin/claude`, authenticated through Claude Max, reports `claude-fable-5`. The older `~/.local/bin/claude` (2.1.81) cannot resolve the configured `fable[1m]` alias. Fable 5.1 was not verified. Native Claude implemented the assembler and 13 tests; Codex integrated it and corrected the short-utterance edge case found by independent review. RED replay lost seven of eight utterances; the final 14 helper tests pass. Final app suite: 170 tests executed, three documented skips, zero failures. Signed device build succeeds.

| Physical iPhone 17 Pro / iOS 26.2 measurement | Before | Final fix |
|---|---:|---:|
| Matched Samantha recording: retained words (raw whitespace count) | 35 | 312 |
| Matched reference: scorer token count | 323 | 323 |
| Matched recording: deletions | 289 | 5 |
| Matched recording: substitutions / insertions | 5 / 1 | 41 / 21 |
| Matched recording: word error rate | 91.33% | 20.74% |
| Matched recording: extraction checks | 0/8 | 2/8 |
| Original extra-scenario recording: retained words | 49 | 520 |

Raw word count and normalized scorer tokens differ; they are not interchangeable. The initial assembly-only run recovered 518 words in the original and 312 in the matched recording. Enabling Apple punctuation changes the original output to 520 words and improves matched extraction from 0/8 to 2/8 without changing its word-error score. File recognition finalized in all compared runs; finalization alone does not establish coverage.

The downstream cause of zero extraction was sentence-wide negation on unpunctuated text. Both request types now set `addsPunctuation = true`, preserving Apple's sentence boundaries while keeping `requiresOnDeviceRecognition = true`. This improves boundary handling without weakening clinical negation rules or rewriting misrecognized drug names. BP 100/65 and ketamine pass in the final matched run; the other six checks fail. Natural vital-sign phrasings, negation scope, wound-packing extraction and clinical-word ASR accuracy remain follow-up work. No claim of clinical readiness or live acoustic accuracy follows from this synthetic file test.

The prior main GitHub run passed package tests but failed the Xcode 26.2 simulator build on a nested weak capture in the audio-overrun callback. The nested task now explicitly captures `[weak self]`; local Xcode 26.6 builds/tests pass. Remote CI must confirm the older compiler result separately.

Matched fixture reproducibility (existing local macOS Samantha voice, no network):

```bash
cd '/Users/ama/TCCC_IOS'
/usr/bin/say -v Samantha -r 145 \
  -f TCCC_IOS/DevTools/Fixtures/valdez_alley.txt \
  -o /private/tmp/valdez_alley.aiff
```

Measured audio duration: 134.381406 seconds. Reference SHA-256: `a8f0696d2585266473b00aa725cf1332db2a334ca30b667878e002399310a5f2`. Measured generated-audio SHA-256: `9f1558c44a39314389f73d33fb2f73ba2f573075f963327b67a9afcd5f62352c` (voice/OS versions may change a later render). Local evidence is retained under `/private/tmp/tccc-speech-coverage/`; the original device recording and preservation archive remain unchanged.

Next delivery slice: benchmark the deterministic extractor against the reference text itself, correct evidenced natural-language/negation gaps, then improve clinical-vocabulary ASR and validate human microphone capture. Keep intake/editor polish behind this capture-to-documentation path.
