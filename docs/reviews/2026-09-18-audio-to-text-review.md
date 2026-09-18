# Audio-to-text architecture review — 18 September 2026

Scope: automatic microphone gain plus the three highest-impact demonstrated
capture defects, reviewed against baseline `c5c7b8c`. Apple Speech remains the
default and recognition remains on-device. Codex led implementation and
verification; native Claude Code performed a bounded source-only Apple capture
audit. No personal recordings were supplied to Claude.

## Automatic gain

All three adapters previously requested iOS voice-processing gain but silently
continued without automatic gain if activation failed. Settings exposed a manual
±20 dB multiplier, Float32 multiplication could clip, Granite's clinical factory
did not receive the shared meter/gain configuration, and meter updates described
unprocessed input.

`AutomaticMicrophoneGain` and `MicrophoneInputProcessor` now select iOS AGC when
actually enabled, otherwise apply a bounded software controller. The fallback
limits boost to 4×, does not increase gain below its low-level threshold, raises
level slowly and attenuates loud input quickly. A common instantaneous limiter
keeps PCM within ±0.89. These are engineering parameters, not a validated speech
quality or noise-classification model. Software boost is not stacked on iOS AGC.

Settings shows AUTOMATIC and the active mode. Apple, Parakeet and Granite process
audio on their serial consumers before archiving/recognition; the meter uses
that processed signal and publishes at approximately 10 Hz. Nonfinite Float32
samples are silenced. Synthetic tests cover quiet input, silence, loud arrivals,
Float32 channel layouts, Int16 extremes, metering and invalid numbers.

Apple documents AGC control through
[isVoiceProcessingAGCEnabled](https://developer.apple.com/documentation/avfaudio/avaudioinputnode/isvoiceprocessingagcenabled).
The implementation checks the actual voice-processing, AGC and bypass state;
it does not assume an undocumented Apple target level.

## 1. Selected speech engine could differ from the running engine

**Impact:** changing Settings could leave the existing recognizer installed,
while later ledger entries used the newly selected engine's name. Capture
ownership and source attribution could therefore disagree.

**Correction:** `CaptureBackendCoordinator` serializes replacement and reserves
a capture lease through startup, recording and finalization. Changes during a
capture apply afterward; Settings says which engine remains active. The actual
capture backend is frozen for transcript evidence, including incomplete and
review-required text. Idle warm-up must finish before retirement. Interruption
resume resets the leased stream before microphone preparation.

**Tests:** controlled streams cover idle replacement, deferred changes through
tail, rapid toggles during release, overlapping starts, stale completion,
shutdown, microphone restart, and source attribution. Integration review found
and corrected warm-up and interruption races before delivery.

## 2. Apple buffered speech received a misleadingly new time boundary

**Impact:** a new Speech framework request was dated when it opened, even when
it replayed older pre-roll or queued audio. An older spoken value could appear
to postdate a manual correction and bypass its protection.

**Correction:** timestamp the earliest sample at the microphone tap, retain
that timestamp through pre-roll and rotation queues, and update one
`SpeechBufferClock` at the sole request-append boundary. Invalid timing is
conservative and requires review rather than granting overwrite authority.

**Tests:** six regressions cover pre-roll, successor queues, delayed live input,
empty requests and invalid timestamps. Tests exercise the production extraction
engine's manual-decision fence and acceptance of genuinely newer speech.

## 3. Saved audio could fail conversion or close before queued writes

**Impact:** Apple and Granite sent hardware-format buffers directly into a fixed
16 kHz mono AAC archive. Granite ignored write failures, tap tasks could outlive file closure, and
an error string could be emitted as a successful clinical final. Results lacked
the request timing used to protect manual decisions.

**Correction:** Apple and Granite share `PCMArchiveWriter`, which converts input
to the exact archive format while Apple recognition still receives native PCM.
For Granite, a bounded, ordered queue owns accepted PCM; both normal and
immediate stop drain it before releasing the writer. Separate writer and recognition identities allow
cancellation without dropping accepted archive buffers. Copy, conversion,
write, overflow and protection failures produce structured failed/cancelled
results. Only successful final text enters extraction; retained incomplete text
remains evidence. No unprotected-file fallback is used.

**Tests:** real synthetic 44.1/48 kHz audio is converted and written to temporary
AAC files; decoded duration, ordered drain, suspended writes, queue overflow,
writer failure and cancelled-waiter drain are checked. App-level tests check
failed/cancelled text, replay, source attribution and manual corrections.

## Validation and limits

- Full TCCCKit suite: **902 tests passed**, no failures.
- iOS Simulator capture/gain/wireless regression suite: **84 tests passed**, no failures.
- Actual AAC archive tests pass in the iOS app test host. The standalone macOS
  helper process could not initialize its AAC encoder; that local limitation
  was not treated as proof of an iOS failure or success.
- Independent source review covered gain/buffer handling, backend lifecycle and
  Granite stop/cancellation. The issues it identified were corrected and retested.
- Signed iPhone build passes with the complete offline model payload.
  In-place deployment is recorded after verification.

Synthetic PCM and controlled streams establish the tested data/lifecycle
behavior. They do not establish improved word accuracy in field noise, acoustic
clipping at the microphone hardware, or model quality on this user's speech.
Granite remains record-then-transcribe; this change does not add streaming
inference. A physical quiet/normal/loud read-aloud remains the acoustic check.
