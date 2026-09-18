# Local wireless vitals direction

## Approved product direction

On 2026-09-18 the owner authorized local wireless sensor support as the next
main development direction, starting with the Vibeat S5W pulse oximeter.
This supersedes the former blanket prohibition on Bluetooth clients.
The owner also authorized integrating these changes into the default branch,
which is named `main` in this repository.

This document records required behavior and implementation boundaries.
It does not claim that Bluetooth transport, auto-connect, or sensor ingestion
is already implemented or verified on a physical iPhone.

## User-visible behavior

- Add a **Wireless sensors** section to the existing Settings/options menu.
- **Automatically connect to pulse oximeter** defaults to **on** when the
  preference has not been set. Persist an explicit off choice across launches.
- When enabled, quietly discover a supported oximeter and attempt connection;
  reconnect to the remembered device after recoverable disconnection.
- Prefer the previously selected device. With no remembered device, allow
  automatic connection to a single unambiguous supported candidate. If there
  are multiple candidates, expose selection in Settings without silently
  switching devices or choosing by signal strength alone.
- Show connection/data status in Settings: disabled, permission needed/denied,
  Bluetooth unavailable/off, searching, connecting, connected awaiting valid
  data, receiving readings, or disconnected. Failure must not cause repeated
  modal alerts or interfere with voice capture.
- Turning the option off stops discovery, cancels pending connection/retry
  work, disconnects the sensor, and prevents delayed callbacks from ingesting
  data. Do not change the phone's system Bluetooth setting.
- Respect iOS Bluetooth permission and radio state. The system permission
  prompt cannot be suppressed by the requirement for quiet operation.
- Support background operation within Core Bluetooth's actual limits. Use
  the `bluetooth-central` background mode and service-filtered discovery where
  supported by the device; do not promise uninterrupted execution after
  force-quit, indefinite polling, or bypasses of iOS scheduling.

## Clinical state and privacy

Offline means no internet dependency during capture or sensor use. Local BLE
is permitted; cloud accounts, vendor apps at runtime, analytics, telemetry,
and automatic uploads remain excluded. Existing operator-gated model
preparation remains governed by the current project policy.

Preserve the event-sourced encounter as the authoritative record. Sensor
evidence must carry device identity, raw frame provenance, receipt time,
device acquisition time when available, encounter association, review status,
decoded units, and known signal/measurement quality. Keep acquisition and
receipt times distinct; never invent a device timestamp. Preserve unknown quality
as unknown. Connection alone is not a valid measurement. Do not infer normal
vitals from missing, malformed, stale, searching, or probe-off data.

Sensor data must be explicitly distinguishable from speech extraction and
operator-entered values. Label consumer sensor values as unvalidated. Keep
operator review authority and existing correction protections. Never write
directly to patient state through a nonlogging path. Replay must reconstruct
the same recorded result without reparsing raw frames.

Connection alone does not establish that a sensor belongs to the active
casualty. Record the operator's device-to-encounter association before adding
readings to the clinical record; an unbound connected sensor may show a clearly
labeled preview without populating patient state.

Reconnect refinement (2026-09-18): after one explicit association, a transient
disconnect pauses recording. The same sensor may automatically resume for the
same active casualty within the current app process. Keep the original consent
and operator-correction protections across the pause, while giving the new
connection a fresh ingestion identity. Stop recording, switching auto-connect
off, changing/ending the casualty, or restarting the app clears that authority.
Another sensor must never inherit it. Settings shows the paused association and
offers Stop while waiting for the sensor to return.

Reset or explicitly rebind ingestion when the active casualty changes, and
reject delayed data from the previous encounter or connection. Do not assign
a reading across casualties merely because a BLE connection remained open.

Keep bench captures, personal readings, and device identifiers private and
outside Git. Commit synthetic fixtures or deliberately sanitized protocol
fixtures after checking that they contain no identifying or personal data.
Preserve complete file protection for persisted encounter data.

## Implementation sequence and exit evidence

1. **Verify the actual S5W protocol.** Discover the designated device on the
   Mac, inspect its GATT services/characteristics, and capture a bounded local
   sample with the vendor app disconnected. Compare decoded values and
   finger-in/finger-out behavior against fresh, user-visible camera images.
   Nordic UART framing, CRC coverage, PI scaling, and status bits in the
   supplied handoff remain hypotheses until observed. An empty scan is
   inconclusive; it is not proof of Bluetooth Classic or incompatibility.
   The owner reports that ViHealth on the Mac connects to the oximeter and
   can be activated for investigation; an iPhone app is also available for
   the same purpose. Keep the vendor apps
   disconnected during direct probing. If a connected device remains silent,
   coordinate a bounded vendor-app capture to identify any startup writes;
   inspect the Mac app first, with the iPhone path available as a fallback.
2. **Implement transport-independent decoding and evidence.** Put parsing and
   typed sensor evidence in TCCCKit. Reject malformed/truncated frames without
   crashing or producing plausible-looking values. Support stream fragments
   and resynchronization if the observed protocol needs them. Retain available
   waveform/quality evidence without treating an attractive waveform as
   clinical validation. Extend the encounter log and logged engine ingestion
   path; do not create a second authoritative patient record.
3. **Implement iOS transport and Settings.** Keep Core Bluetooth platform
   plumbing in the app layer, with testable connection decisions in the
   package. Load the saved setting before starting transport. Use cancellable,
   bounded retries and distinguish transport connection from valid data.
   Add `NSBluetoothAlwaysUsageDescription` and the required background mode
   through `project.yml`, then regenerate the Xcode project.
4. **Verify and integrate into main.** Check decoder failures, persisted off
   state, cancellation during connection, reconnect, stale/probe-off data,
   ambiguous devices, encounter changes, and event-log replay. Run relevant
   package checks and an app build. Validate actual display values, disconnect,
   and background behavior on the connected iPhone before claiming physical
   sensor support. Keep source/build validation separate from device results.

The initial device is the S5W. A blood-pressure cuff and other sensor families
can follow after this path works; their SDKs, account requirements, and
protocols are not prerequisites for the pulse-oximeter integration.

## Current code boundaries

- Settings: `TCCC_IOS/Components/SettingsOverlay.swift`.
- App preferences/lifecycle: `TCCC_IOS/App/AppState.swift` and app entry points.
- Platform declarations: `project.yml`.
- Existing vitals: `Packages/TCCCKit/Sources/TCCCDomain/Vitals.swift`.
- Evidence/log: `Packages/TCCCKit/Sources/TCCCExtractor/EncounterEvent.swift`.
- Logged mutations/replay: `Packages/TCCCKit/Sources/TCCCExtractor/PatientStateEngine.swift`.

At this review, no Swift `VitalsSensor` declaration exists. The Section C grid
is a four-reading snapshot view, not a complete raw sensor history. Determine
the final sensor interfaces from observed frames and these existing boundaries
before dividing implementation among workers.

## Platform references

- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
  documents the Bluetooth usage-description requirement.
- [Apple background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
  describes background modes, discovery differences, and power constraints.
- [Bleak macOS backend](https://bleak.readthedocs.io/en/latest/backends/macos.html)
  documents macOS permissions and Core Bluetooth behavior for bench discovery.
