# DevTools Coverage Gaps

- Simulator microphone input can verify permission and lifecycle behavior, but it cannot prove real ambient dBFS sampling fidelity. Confirm `AmbientMeter` on device with an actual microphone before treating the pre-roll level as operationally representative.

## Current Device Lane

- Per user direction on 2026-05-07, Codex targets `Default15` / iPhone 15 Pro (`00008130-000E78E210FA8D3A`, CoreDevice `DF20767D-0672-56DB-9928-AD2191C2CCA5`). Claude owns the iPhone 17 lane.
- The integrated app builds for the iPhone 15 physical destination with `CODE_SIGNING_ALLOWED=NO`.
- A signed Debug build also succeeded for iPhone 15 using `Apple Development: Aaron Arzamendi (434HG698U6)` and `iOS Team Provisioning Profile: *`.
- The signed app installed on iPhone 15 as `com.aarzamen.TCCCai` and launched successfully via `devicectl`; launch output reported PID `4036`.
- No automated on-device tap-walk is recorded here. The device tooling verified install and foreground launch, not visual inspection of each button state.

## Playback Limitations

- Simulator builds can verify the Sender readout layout, transport-control state, and Kokoro unavailable/failed messaging, but they do not prove native Kokoro synthesis because the conversion path is intentionally blocked.
- Playback visualization requires a real audio URL loaded through `AVAudioPlayer` metering. Without that URL, the expected simulator behavior is an inactive flat waveform and zero VU.
- Sentence highlighting depends on Kokoro sentence timing metadata. Without timing metadata, simulator coverage is limited to confirming the full script remains visible and unmodified.
- The 500-word Kokoro peak RSS acceptance check cannot be run until native Kokoro synthesis exists. The current implementation fails closed before allocating model weights.
