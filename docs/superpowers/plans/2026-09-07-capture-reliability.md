# Capture reliability sprint

Authority: [PROJECT_POLICY.md](../../../PROJECT_POLICY.md). GPT-6 owns delivery and GitHub housekeeping. Target: a technically worthwhile iOS demonstration for the NMRTU Navy medical technology team in approximately one to two weeks.

## Delivered feature slice — 2026-09-08

- Unknown casualty name, unit, service-number suffix and allergies stay blank in the card and PDF. Explicit metadata and NKDA remain valid. NEW, END and WIPE clear casualty identity.
- Protected streamed writes use the supported file-attribute setter and propagate failures. Audio filenames are unique across rapid restarts.
- Apple Speech uses ordered audio and result streams, request identity, bounded pending audio, a 30-second STOP tail and a five-second finalization drain. Audio collected during finalization goes to the successor request. Capture failure is visible; stale callbacks cannot mutate another capture.
- Partials remain visible previews. Finalized requests enter clinical extraction once. Incomplete or superseded text is durable, labeled audit evidence, with no clinical-state mutation. An operator decision after request-open blocks delayed automatic extraction. Encounter changes clear pre-roll.
- Benchmark schema v2 retains finalized, timedOut, failed, cancelled and notStarted outcomes, callback/timing evidence, partial text, warnings and explicit unavailable scores. A finalized recognizer result does not establish whole-file coverage. Benchmark artifacts use protected writes.

## Verification

| Gate | Result |
|---|---|
| Clinical package | 793 tests, zero failures |
| Simulator app integration | 152 tests, 3 skipped, zero failures |
| Physical iPhone 17 Pro, iOS 26.2 | Both synthetic persistence tests pass, including strict complete file protection |
| Signed device build | Succeeds |
| Integration review | Record lockout, operator-before-first-callback gap, and old-casualty pre-roll findings fixed and confirmed |

The simulator cannot establish the iOS file-protection class when its backing filesystem omits the attribute; that one assertion runs on physical iOS. The two other simulator skips require optional Granite model assets. The new benchmark encoder, summary formatter, callback contract, capture identity and lifecycle cases are included in the app test gate.

Existing device preservation was reused. No repeated backup or repository-recovery cycle was performed. Private recordings, device data, worker traces and detailed local test artifacts are not repository content.

The physical-device file benchmark completed with schema v2: 761 callbacks, first hypothesis at 0.337 seconds, finalized at 8.907 seconds. It retained 49 hypothesis words against 323 reference words: 271 deletions, six substitutions, 85.76% word error rate, 23.08% keyword recall and 1/8 extraction assertions passed. This is a failed speech-coverage result despite successful recognizer finalization. Raw recordings and transcripts remain private. File recognition and live microphone capture are different paths; this result does not establish live accuracy in either direction.

## Remaining demonstration work

Live-microphone acoustic accuracy, long uninterrupted narration, real-room noise and clinical extraction accuracy are not established by callback tests or a signed build. Use the authored scenario for a timed live recording, inspect retained text against the source, and measure missed/corrected facts before presenting acoustic performance claims.

The next priority is speech coverage: reproduce the missing-file-text behavior, preserve the complete utterance sequence and compare a timed live capture against the same authored scenario. Then complete operator correction and real casualty intake through the handoff: enter identity, review/correct documentation, export a usable DD1380, and recover the encounter after relaunch. Official-form overlay and practical tester distribution remain explicit follow-throughs. Keep optional backend and hardware expansion behind this demonstration path.
