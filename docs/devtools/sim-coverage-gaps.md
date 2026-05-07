# DevTools Coverage Gaps

- Simulator microphone input can verify permission and lifecycle behavior, but it cannot prove real ambient dBFS sampling fidelity. Confirm `AmbientMeter` on device with an actual microphone before treating the pre-roll level as operationally representative.

## Current Device Lane

- Per user direction on 2026-05-07, Codex targets `Default15` / iPhone 15 Pro (`00008130-000E78E210FA8D3A`, CoreDevice `DF20767D-0672-56DB-9928-AD2191C2CCA5`). Claude owns the iPhone 17 lane.
- The integrated app builds for the iPhone 15 physical destination with `CODE_SIGNING_ALLOWED=NO`.
- A signed Debug build also succeeded for iPhone 15 using `Apple Development: Aaron Arzamendi (434HG698U6)` and `iOS Team Provisioning Profile: *`.
- The signed app installed on iPhone 15 as `com.aarzamen.TCCCai` and launched successfully via `devicectl`; launch output reported PID `4036`.
- No automated on-device tap-walk is recorded here. The device tooling verified install and foreground launch, not visual inspection of each button state.

## Playback Limitations

- The active sender renderer now tries FluidAudio Kokoro CoreML first, then falls back to iOS device speech synthesis. Both paths render a real WAV file, then play that file through `AVAudioPlayer` so the visualization is driven by actual metering.
- Focused iPhone 15 tests verified the wrapper seam and the fallback real device renderer for a short phrase. They do not prove FluidAudio model availability, first-run download behavior, or voice quality across every installed iOS voice.
- Sentence highlighting is sentence-level and estimated from the generated file duration plus sentence word counts. Word-level forced alignment remains out of scope.
- A 500-word end-to-end DevTools playback walk is still worth doing before calling the sender flow polished. If FluidAudio Kokoro runs on device, profile RSS separately from the iOS speech fallback.
