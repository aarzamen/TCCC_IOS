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

## Runtime blocker

The exact blocker is that the available Kokoro artifacts are PyTorch-only:
`/Users/ama/Kokoro-82M/kokoro-v1_0.pth` plus `.pt` voice tensors. There is no Core ML, MLX Swift, or Swift/iOS runtime artifact to load. Enabling synthesis requires explicit confirmation of a PyTorch-to-native conversion path, including the model, voices, and text-to-phoneme/G2P path.

Per the spec, no conversion has been attempted. The app boundary throws `KokoroEngineError.nativeRuntimeUnavailable(.pythonPyTorchOnly)` rather than falling back to Apple speech or fake audio.

## Implemented boundary

`TCCC_IOS/DevTools/TTS/KokoroEngine.swift` provides:

- `KokoroEngine.voices`: embedded voice catalog from local `VOICES.md` and `voices/*.pt` names.
- `KokoroEngine.defaultVoiceID`: `af_heart`.
- `availableVoices`: compatibility property for the current sender UI.
- `synthesize(text:voice:speed:pitchSemitones:)`: direct async API for future callers.
- `synthesize(_ request:)`: compatibility adapter for the current `SenderViewModel`.

The file imports only `Foundation`. It does not import `AVFoundation`, `FoundationModels`, or `SystemLanguageModel`, and it does not create placeholder audio.
