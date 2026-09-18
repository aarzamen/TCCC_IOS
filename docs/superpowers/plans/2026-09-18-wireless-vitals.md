# Wireless vitals implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to execute the bounded tasks below. Codex leads integration; native Claude Code owns the isolated transport assignment.

**Goal:** Connect the S5W locally, preview readings, and record explicitly associated consumer-sensor evidence without compromising operator corrections or encounter replay.

**Architecture:** Foundation-only decoding in TCCCDomain feeds typed atomic evidence events in TCCCExtractor. Core Bluetooth plumbing stays in the app; AppState fences asynchronous work by connection, association, encounter identity, and persistence directory. The existing event log remains authoritative.

**Tech stack:** Swift 6, iOS 26, Core Bluetooth, SwiftUI, existing TCCCKit; no new runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-wireless-vitals-direction.md`

## Global constraints

- Automatically connect to pulse oximeter defaults to on; persist explicit off and cancel scanning, connections, retries and ingestion when off.
- Preserve on-device runtime, complete file protection, event-sourced clinical state, operator review authority and truthful unknown values.
- Keep bench captures, personal readings, and device identifiers private and outside Git.
- Record an operator device-to-encounter association before adding readings to clinical state.
- Label consumer sensor values as unvalidated; never infer device acquisition time or signal-quality flags.
- Preserve iPhone-only landscape UI and gloved-hand controls of at least 44 points.
- Work on the authorized default `main`; workers own distinct files or isolated temporary copies. Codex reviews and publishes.

## Task 1: Protocol decoder and typed evidence

**Files:** new `Packages/TCCCKit/Sources/TCCCDomain/PulseOximeter.swift` and `Tests/TCCCDomainTests/PulseOximeterTests.swift`.

**Interfaces:** `PulseOximeterReading` has UUID id, receipt/acquisition times, optional SpO2/pulse/PI, raw frame, protocol version, and quality (`unknown`, `unavailable`, `unsupportedEncoding`). `PulseOximeterWaveform` retains receipt time, raw frame and amplitude bytes. `LepuPulseOximeterDecoder.append(_:receivedAt:)` yields reading/waveform packets and supports `reset()`.

- [x] Test synthetic frames, fragmented/concatenated notifications, corruption, length recovery, zero sentinels and unsupported pulse extension encoding.
- [x] Decode AA55, total length = byte 3 + 4, whole-frame CRC8/MAXIM remainder zero. Numeric offsets 5/6/8 are saturation, low pulse byte and PI tenths. Nonzero pulse extension byte remains unsupported until verified; unknown flags remain unknown.
- [x] Preserve unknown frames as evidence where available; never turn malformed data into plausible vitals. Do not copy third-party protocol implementation code.
- [x] Run `swift test --filter PulseOximeterTests` from the package and review the diff.

## Task 2: Atomic event-sourced ingestion

**Files:** extractor `EncounterEvent.swift`, `PatientStateEngine.swift`, projection implementation, new `SensorEvidence.swift`; new `SensorEvidenceTests.swift`.

**Interfaces:**

```swift
associateSensor(deviceID: String, deviceName: String, connectionID: UUID,
                encounterID: UUID, patientId: String = "PATIENT_1",
                timestamp: Date = Date()) -> SensorAssociationPayload?
revokeSensorAssociation(associationID: String? = nil, timestamp: Date)
recordSensorObservation(reading: PulseOximeterReading,
    waveforms: [PulseOximeterWaveform], associationID: String,
    connectionID: UUID, encounterID: UUID,
    auxiliaryFrames: [PulseOximeterRawFrame] = [], timestamp: Date) -> SensorObservationPayload?
```

- [x] Add association/revocation and observation log cases; observation embeds raw evidence and applied deltas in one append for crash-safe replay.
- [x] Reject mismatched binding and duplicate readings; retain stale readings as evidence without applying values. Restore never restores live association authority. Settle provisional speech before appending sensor evidence.
- [x] Preserve post-association operator decisions for HR/SpO2 until explicit rebind; invalid readings retain evidence without erasing historical valid values.
- [x] Verify Codable roundtrip, replay equivalence, manual protection, provisional interleaving, duplicate/late samples, encounter/connection mismatch and old-log restore using synthetic fixtures.

## Task 3: Native Claude transport

**Files:** new `TCCC_IOS/Sensors/PulseOximeterBluetooth.swift`, authored in an isolated temporary directory by native Claude Code.

**Interfaces:** MainActor observable transport exposes status, candidates, connected device, connection ID, persisted default-on flag, lifecycle methods, selection, raw notification callback, and synchronous invalidation callback. Parent decoder marks valid/unavailable readings explicitly.

- [x] Load preference before CBCentralManager creation; suppress power-alert spam.
- [x] First discovery uses supported names and a bounded candidate-selection window while scanning in the foreground because the observed device does not advertise service UUIDs. Prefer remembered identity; expose ambiguous selection and handle later arrivals.
- [x] Subscribe to NUS TX without startup writes. Reconnect remembered device in background subject to iOS scheduling. Retry after 2/4/8/16/30 seconds, then continue with a 60-second cooldown while enabled.
- [x] Off/disconnect/state changes invalidate the session before delayed callbacks. Stale valid-data status expires after five seconds.
- [x] Independently typecheck in Swift 6 against the installed iOS Simulator SDK and review callback races.

## Task 4: App association, preview, persistence and provenance

**Files:** `App/AppState.swift`, new `App/AppState+WirelessSensors.swift`, `App/EncounterStore.swift`, `Components/SettingsOverlay.swift`, `Screens/VitalsScreen.swift`, `App/HandoffData.swift`, app entry point, `project.yml`; focused app tests.

- [x] Start transport after encounter restore; route foreground/background lifecycle.
- [x] Show Settings switch, connection state, candidate selection and preview. Provide a deliberate association/rebind action naming the current casualty and a stop-recording action.
- [x] Serialize ingestion with captured engine/encounter/directory and invalidate synchronously before lifecycle awaits. Guard persistence against old-directory callbacks; cancel and drain every outstanding ingestion task, recheck after awaits, and block binding throughout encounter transitions.
- [x] Record sample-only Section C values, receipt-time provenance, unvalidated label and CSV source metadata. Keep one latest automatic column alongside up to three operator/speech columns; retain every recorded sensor observation in the event log. Do not copy old BP/RR into a fresh sensor column. Recover the latest automatic column from authoritative events.
- [x] Add Bluetooth usage description and `bluetooth-central` via XcodeGen.
- [x] Verify focused persistence/provenance tests, package suite and simulator build; independently review the combined change and the final corrections.

## Task 5: Physical acceptance and delivery

- [x] Mac direct connection and automatic NUS stream with vendor apps disconnected.
- [x] Bounded local capture confirms frame lengths and CRC. Personal captures stay outside Git.
- [x] Final signed iPhone build after all source fixes passed at 07:51 local with `TCCC_REQUIRE_OFFLINE_MODELS=YES`.
- [x] Operator confirms the physical iPhone records sensor values correctly and feeds them into TCCC.
- [ ] Complete field-level display comparison and on-phone finger-out invalidation checks.
- [x] Update the connected iPhone without uninstalling; launch and confirm the process remains running. Complete offline model assets are included.
- [ ] Verify on-phone default-on, permission flow, explicit off, detailed association flow, reconnect, encounter change and background behavior.
- [x] Record completed source/build checks and the remaining physical acceptance boundary in [the validation record](../../testing/2026-09-18-wireless-vitals-validation.md).
- [x] Commit and push reviewed, software-verified source to main under standing authorization (`d71ca27`).
- [ ] Complete the remaining physical acceptance checks and record their results separately from installation success.

## Software completion and review

The complete TCCCKit suite passed **880 tests, zero failures**. Focused app
regressions passed **44 tests, zero failures**; after the latest automatic-column
change, the three affected app suites passed **20 tests, zero failures**
(Wireless 10, CSV 8, Section C 2). These are separate runs, not additive counts.
The simulator Settings UI was checked in landscape: auto-connect initially on,
off displayed "Sensor connection off", and on displayed "Bluetooth unavailable"
as expected on the simulator. The layout was readable and the setting was
returned to on. This does not establish physical Bluetooth behavior.

All integration review findings are resolved in source: cancellation covers
the complete queued task chain and actor entry; lifecycle gates prevent rebinding
during rotation; atomic snapshots reconcile values, provenance and actual binding
authority; bounded uninterpreted frames retain receipt provenance; retries continue
at the quiet cooldown; and the automatic grid column preserves manual history.
Independent scoped rereviews found no remaining actionable issue in those fixes.
Physical iPhone installation, launch and process presence are confirmed at
07:55 local. The operator subsequently confirmed correct values, recording and
ingestion into TCCC on that iPhone. Remaining lifecycle and background checks
are tracked separately; the report does not establish clinical accuracy.

## Execution notes

- Same-casualty reconnect refinement: one explicit association survives a
  transient link loss within the current process, preserving manual decisions.
  Stop/Off, casualty change and relaunch still clear it. Engine/app changes and
  independent review are complete; 897 package tests, 35 focused app tests and
  the final 20 wireless tests pass. See the validation record for the separate
  updated-build and physical acceptance status.

- Raw status bits, high pulse extension, waveform flag meanings, and device acquisition time are not verified. Preserve evidence and unknowns; unsupported encoding must not fabricate values.
- No promise of first-time background discovery or continuous execution after force-quit. Hardware checks remain separate from source/build validation.
