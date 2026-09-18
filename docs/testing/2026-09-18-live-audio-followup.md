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
review. These thresholds passed deterministic regressions. The subsequent
on-device read-aloud result is recorded below.

- Signed generic iOS build **bfdbfb2** passed with the complete offline payload:
  154 files, 5,749,615,321 bytes. The embedded build stamp identifies a clean
  `main` source checkout.
- Updated the connected iPhone 17 Pro in place at approximately 11:50 local
  time on 18 September 2026. Installation and launch succeeded; process
  inspection confirmed the app running. File metadata confirmed the test
  recording, encounter event log, Section C data and manifest remained present.
- Source commit **bfdbfb2** is pushed to `main`. The operator subsequently
  completed the requested two-volume test on this build.

## Physical retest

The new recording and encounter artifacts were retrieved directly from the
connected iPhone after the operator finished the test. The durable manifest
confirmed that New Casualty advanced beyond the previously saved labels.

Both volume passes produced separate, successful Apple Speech final segments.
Each contained all four requested fictional values correctly: pulse 120,
blood pressure 90/60, respiratory rate 22 and oxygen saturation 96%. The
persisted Section C data matched those values. There were no incomplete
segments and no hemorrhage deltas from the blood-pressure phrase.

The repeated identical values intentionally produced one Section C row. Both
spoken observations remain in the event log; the second advances the update
time without duplicating unchanged vital-value deltas. This matches the current
engine and Section C deduplication behavior.

The 72.8-second AAC file decoded successfully (16 kHz mono). Decoded audio had
zero full-scale samples and a peak of approximately -2.5 dBFS. Both the quieter
and louder speech intervals were present. This establishes a successful local
capture-to-persisted-values check for the requested phrase, not general speech
accuracy or performance in field noise. A nonclinical introductory word was
still misrecognized; the requested vital values were correct in both passes.

No source behavior changed for this validation; the 918 package and 136 app
test results above remain the checks for the installed source. Personal audio,
raw event logs and device identifiers remain outside the repository.

## Session closeout: footer and silent-tail status

The operator's later screenshot showed five clipped footer controls and a
"No speech detected" error after the successful read-aloud. The correct saved
values above remain valid; the status error is a separate completion defect.

The footer previously lived inside each clipped page. Capture content with a
minimum height could displace both the page heading and footer outside the
viewport. One shared footer now reserves its own height in the main shell,
above the device's bottom safe area. Page navigation still updates with the
selected screen. A compact meter and a scrollable auxiliary-control area keep
the capture heading, Record/Mark buttons and actual error text visible on the
iPhone landscape layout. All five footer controls retain 44-point hit targets.

Apple's documented `kAFAssistantErrorDomain / 1110` means no recognized speech.
The recognizer now accepts that as an empty completion only for a deliberately
ended, entirely quiet successor after earlier successful speech. Retained text,
unsafe-boundary quarantine, audible/invalid PCM, initial no-speech failures and
other errors still fail truthfully. Empty completion follows the existing
request lifecycle; it neither shortens the remaining recording tail nor erases
earlier errors. See [Apple's error reference](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/error).

Verification for these closeout corrections:

- Full package suite: **926 tests passed**, zero failures.
- **9 focused app tests passed**, covering capture lifecycle, request boundaries
  and the two new quiet-successor completion cases.
- The new empty-successor package regressions failed before the correction.
- A temporary render probe reproduced the original clipping at the iPhone's
  landscape content size. The updated footer was inspected on all five pages.
  Hosted SwiftUI screenshots at 874 × 402 points also confirmed full visibility
  of footer icons/labels, capture controls and error text, with real safe areas
  and populated scrolling content. Probe source and images remain local; the
  temporary test was removed from the shipping project.
- Independent source reviews found no remaining actionable issue in the
  footer/navigation/overlay behavior or the empty-successor correction.

Signed build **32f67cd** passed with all 154 offline-model files
(5,749,615,321 bytes). It was installed in place on the connected iPhone 17 Pro
at approximately 12:52 local time on 18 September 2026. Launch and process
inspection succeeded; the previous encounter/recording paths remained present.
Source is pushed to `main`. A fresh physical silent-tail status check and the
earlier same-casualty sensor-recording resume acceptance remain separate from
the completed two-volume value check; neither is claimed from simulator tests.

Native Claude Code contributed a scoped, source-only partial implementation of
the numbering correction. It reached its turn limit; Codex completed, reviewed
and tested the integrated change. Claude received no recordings or device data.
