# Agent B Self-Review

Scope reviewed: `TCCC_IOS/DevTools/TTS/KokoroEngine.swift` and Kokoro runtime notes.

## Findings

- The local Kokoro repo still has PyTorch assets only, so native Kokoro model inference remains deferred.
- Per the user's later direction that any compatible TTS engine is acceptable, the active sender path now renders real on-device WAV audio with `AVSpeechSynthesizer.write`.
- No Apple Foundation Models, `SystemLanguageModel`, `FoundationModels`, cloud service, or fake audio fallback is present in the TTS boundary.
- The default voice is `af_heart`.
- Voice picker data is embedded from Kokoro voice names in local `VOICES.md` and `voices/*.pt`.
- License bundling is not complete because the local checkout has README frontmatter declaring Apache-2.0 but no standalone `LICENSE` file.

## Fixes applied

- Replaced the typed native-runtime blocker with a real device renderer that writes playable audio to a temporary WAV file.
- Kept `KokoroEngine.defaultVoiceID`, `KokoroEngine.voices`, and `availableVoices` for the current sender UI.
- Added the requested direct API: `synthesize(text:voice:speed:pitchSemitones:)`.
- Kept the current `synthesize(_ request:)` adapter so `SenderViewModel` can route through the compatibility wrapper.
- Added validation for empty script, unknown voice, speed, and pitch before rendering starts.

## Build note

The orchestrated integration pass regenerated the Xcode project, added focused engine tests, and verified the active device TTS path on the connected iPhone 15. Native Kokoro conversion remains documented as a future path rather than a runtime blocker.
