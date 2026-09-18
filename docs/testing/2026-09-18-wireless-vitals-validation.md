# Wireless vitals validation — 18 September 2026

## Scope and provenance

The first implementation targets S5W-family pulse oximeters using the observed
Nordic UART notification stream. It is a consumer-sensor integration with
unknown signal quality, not a claim of clinical validation. The app labels
sensor values accordingly. Acquisition time is unknown; receipt time is kept
explicitly. Other sensor families and unverified high pulse encodings are not
claimed supported.

Native Claude Code 2.1.267 authored the isolated Core Bluetooth transport in
two finite, restricted coding runs. Codex reviewed the source, corrected retry
behavior, implemented the application integration, and independently verified
decoding and persistence. No private sensor captures, identifiers, credentials,
recordings or encounter data were provided to Claude.

## Bench evidence

With ViHealth disconnected on the Mac and phone, the designated S5W connected
directly on the Mac and began streaming notifications without an application
startup write. It advertised a supported local name but no service UUIDs.
First-time discovery therefore uses a bounded candidate-selection window
while the iOS app is open; background reconnection uses a remembered identity.

Observed service: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`.
Notification characteristic: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`.
The write characteristic and the additional proprietary service are unused.

Two 60-second captures completed without disconnection. The separate finger-out
capture ended after 55 notifications and a final unavailable all-zero numeric
frame. The operator independently observed the display report finger-out,
then shut down. Reinsert/restart and reconnect still need end-to-end iPhone
acceptance; the terminated Mac capture does not establish those behaviors.

The actual Swift decoder was checked privately against all 1,585 frames:
125 numeric frames, 1,219 waveform frames and 241 uninterpreted frames.
Independent CRC calculation, bytewise/concatenated delivery, receipt timestamps,
decoded offsets, raw evidence and 1,344 corrupted-frame recovery cases matched.
No personal numerical readings or device identifiers are recorded here.

Frames use AA55 sync, byte-3 length plus four bytes, and CRC8/MAXIM across the
entire frame with remainder zero. Known numeric and waveform lengths are
checked before decoding. Zero values are unavailable. Nonzero pulse extension
encodings remain unsupported. Status flags, battery mapping and waveform flag
meanings remain uninterpreted, with original evidence retained.

The camera preview showed every inspected still in a 360 by 270 point floating
window. Display glare prevented a conclusive pixel-level comparison of every
numeric field, especially PI. Frame decoding evidence must not be described as
complete physical display matching.

Public references: the manufacturer's [LepuDemo device documentation](https://github.com/viatom-develop/LepuDemo)
groups S5W with its PC-60FW family; [Apple's Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
defines execution and discovery constraints. The implementation is independently
authored; no third-party protocol implementation was copied.

## Software checks and acceptance record

- Decoder suite: 22 synthetic tests passed, including an independent standard
  CRC check, zero sentinels, unsupported extension, corrupt lengths, fragmented
  streams, nested sync and delayed recovery preserving receipt time.
- Final focused package run: 44 tests passed, zero failures (22 decoder and
  22 sensor-evidence tests).
- Final complete TCCCKit suite: **880 tests passed, zero failures**.
- Focused app regressions: **44 tests passed, zero failures**. After the latest
  automatic-column change, the three affected suites passed **20 tests, zero
  failures**: Wireless 10, CSV 8, Section C 2. These separate runs are not summed.
- App checks cover saved-off behavior, sample-only Section C values, CSV/QR/PDF
  provenance, old-schema decoding, crash recovery, directory fencing, canceled
  ingestion chains, association reconciliation and lifecycle transition gates.
- The final signed iPhone build after all source fixes passed at 07:51 local
  with `TCCC_REQUIRE_OFFLINE_MODELS=YES`; the asset verifier confirmed
  5,749,589,446 bytes. `devicectl` successfully updated the connected iPhone
  17 Pro without uninstalling the existing app, launched it at 07:55 local,
  and a subsequent process query confirmed it remained running. This does
  not establish model readiness or on-phone Bluetooth behavior.
- The actual simulator Settings UI was checked in landscape through CUA.
  Auto-connect was initially on. Switching off displayed "Sensor connection
  off"; switching on displayed "Bluetooth unavailable", matching the simulator
  environment. Layout was readable, and the setting was returned to on.

## Resolved integration review

- Stop/Off and lifecycle invalidation cancel every outstanding ingestion task,
  then drain the chain. The app rechecks identity and cancellation after storage
  awaits; the engine rejects canceled ingestion at entry.
- New Casualty, End Care and Wipe gate new bindings before their first await
  and until completion. Atomic snapshots return clinical values, provenance
  and active binding authority together; stale snapshots cannot tear down a
  newer association.
- Checksum-valid uninterpreted frames retain bounded raw bytes and receipt
  times with numeric observations, filtered to the active association and
  receipt window. No status or battery meanings are inferred. Older events
  without this optional evidence still decode.
- Automatic connection uses delays of 2/4/8/16/30 seconds, then a continuing
  60-second cooldown while enabled. It does not permanently exhaust its
  retry budget; disabling still cancels pending work.
- The Section C grid keeps one latest automatic sensor column alongside up to
  three operator/speech columns. A 1 Hz stream no longer replaces the manual
  columns every few seconds. Each retained column keeps its own source and
  timestamp; every recorded sensor observation remains in the event log.
  Recovery reconstructs the latest automatic column from that log.

The combined change and each correction received an independent scoped review.
All reported integration findings are resolved in source. The latest grid
regression preserves three manual BP columns through eight sensor observations
and verifies that all eight observations remain in the event log.

## Physical iPhone acceptance

After the updated build was installed on the iPhone 17 Pro, the operator
confirmed that the sensor records, the displayed values are correct, and the
readings feed into TCCC. This establishes operator-observed end-to-end live
sensor ingestion on the physical iPhone. No personal values or captures are
included in this record. The report does not establish clinical accuracy,
each protocol field, export round trips or persistence after relaunch.

Remaining physical checks are:

- Default-on discovery and OS permission flow, explicit off across relaunch,
  unbound preview, and the detailed casualty-association flow.
- Finger-out unavailability and the refined automatic association-resume flow.
- Rebinding across encounters, cancellation during connection, and actual
  background behavior within iOS scheduling limits.
- Persistence after relaunch and export round trips for a recorded sensor
  encounter; field-level comparison beyond the operator-confirmed readings.

The Mac frame checks and finger-out observation above remain separate evidence;
they do not establish the remaining iPhone behaviors.

The operator subsequently reported that the installed build reconnects and
picks up the data source without intervention, but requires an awkward manual
patient re-association. This confirms operator-observed transport reconnection
for that run; it is the motivation for retaining same-sensor, same-casualty
consent across transient interruptions. The refined automatic recording-resume
behavior requires its own software and updated-device verification.

## Same-casualty recording resume refinement

The revised implementation suspends the original in-memory association on a
transport interruption and resumes it only for the same sensor and active
casualty. Every connection receives a fresh ingestion token. Manual corrections
before and during the pause remain protected. Stop/Off, patient or encounter
changes, and process restart clear the retained authority. Settings shows the
paused recording and retains its Stop action.

Native Claude Code contributed the engine suspension/resumption implementation
in a bounded isolated run. Codex reviewed and integrated it, added the atomic
suspended-state snapshot, and implemented and verified app coordination. Only
curated source and synthetic fixtures were provided to the worker.

Verification after this refinement:

- The regression first reproduced the old disconnect-to-revocation behavior.
- All **897 package tests passed**, including **39 sensor-evidence tests**.
- **35 focused app tests passed**, covering reconnect, corrections, old
  callbacks, alternate sensors, Off, persistence, provisional speech and exports.
- After the final snapshot timing correction, all **20 wireless app tests
  passed** (16 integration tests and four controlled interruption-race tests).
  These runs are separate, not additive test totals.
- The app tests substitute only the Bluetooth transport; the decoder, engine,
  event persistence and resume orchestration use production code. The race
  tests explicitly interrupt a resume after the engine creates the new binding
  but before the app publishes it, including a second loss, Stop, a newer
  explicit association and a patient-switch snapshot.
- The signed iPhone build succeeded with complete offline assets enabled;
  the verifier again confirmed 5,749,589,446 asset bytes.

The earlier operator-confirmed automatic radio reconnection is distinct from
this refined recording-resume behavior. Installation of the updated build is
underway; the physical recheck remains pending at this checkpoint.

## Repository delivery

The reviewed implementation is committed and pushed to `main` as `d71ca27`
(`feat: integrate local pulse oximeter vitals`). Private captures, identifiers,
model weights and worker logs remain outside the repository.
