# Kokoro Runtime Notes

Checked `/Users/ama/Kokoro-82M` on 2026-05-07.

## Local asset state

- Present: `kokoro-v1_0.pth`, a PyTorch checkpoint around 312 MB.
- Present: `voices/*.pt`, 54 Kokoro voice tensors including `af_heart.pt`.
- Present: `README.md`, `VOICES.md`, `config.json`, and sample `.wav` files.
- Absent: standalone `LICENSE` file.
- Absent: Core ML model, MLX Swift package, Swift inference code, or iOS phoneme/G2P pipeline.
- Absent in this clone: Python source files. The README usage path installs the Python `kokoro` package and uses `torch`, `soundfile`, `misaki`, and `espeak-ng`.

The README frontmatter declares `license: apache-2.0`, but a real Apache-2.0 license file still needs to be sourced before model or voice assets are bundled.

## Local-clone blocker

The exact blocker is that the available Kokoro artifacts are PyTorch-only:
`/Users/ama/Kokoro-82M/kokoro-v1_0.pth` plus `.pt` voice tensors. There is no Core ML, MLX Swift, or Swift/iOS runtime artifact to load. Enabling synthesis requires explicit confirmation of a PyTorch-to-native conversion path, including the model, voices, and text-to-phoneme/G2P path.

Per the original Kokoro-only spec, no conversion was attempted before user confirmation.

## Compatible native path found

FluidAudio is already in the app dependency graph and ships Swift/CoreML Kokoro APIs:

- `KokoroTtsManager`: multi-voice, long-form chunking, SSML/custom lexicon, CoreML single-graph Kokoro.
- `KokoroAneManager`: faster 7-stage ANE path, single English voice (`af_heart`), shorter utterance limit.

The development Mac already has FluidAudio Kokoro assets cached:

- `/Users/ama/.cache/fluidaudio/Models/kokoro` at about 726 MB.
- `/Users/ama/Library/Caches/fluidaudio/Models/kokoro` at about 620 MB.

This is much lighter than the ChoiceVoice/Qwen3-TTS path, which relies on a Mac-side Tauri/Python sidecar with `mlx-audio` and a 1.7B Qwen model. ChoiceVoice is useful proof that local TTS works on the Mac, but it is not an iPhone drop-in.

## Implemented boundary

`TCCC_IOS/DevTools/TTS/KokoroEngine.swift` provides:

- `KokoroEngine.voices`: embedded voice catalog from local `VOICES.md` and `voices/*.pt` names.
- `KokoroEngine.defaultVoiceID`: `af_heart`.
- `availableVoices`: compatibility property for the current sender UI.
- `synthesize(text:voice:speed:pitchSemitones:)`: direct async API for future callers.
- `synthesize(_ request:)`: compatibility adapter for the current `SenderViewModel`.

## 2026-05-07 Update

The user broadened the engine requirement from Kokoro-only to any working local TTS engine, then called out ChoiceVoice's memory footprint as too large for this path. The app now tries FluidAudio Kokoro CoreML first and falls back to `AVSpeechSynthesizer.write(_:toBufferCallback:)` if model assets are missing, unavailable, or fail to initialize. Both paths render a real WAV file on device, then the existing readout player uses `AVAudioPlayer` for playback, volume, scrub, and metering-driven visualization.

The Kokoro voice IDs remain in the picker as compatibility aliases. FluidAudio receives American English Kokoro IDs (`af_*` / `am_*`) directly and falls back to `af_heart` for currently untested non-American voices. If FluidAudio falls back to iOS speech, the fallback maps voice IDs to the closest installed offline iOS speech voice by language. This is not Apple Foundation Models, `SystemLanguageModel`, Apple Intelligence, cloud TTS, or fake audio.
