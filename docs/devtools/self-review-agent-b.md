# Agent B Self-Review

Scope reviewed: `TCCC_IOS/DevTools/TTS/KokoroEngine.swift` and Kokoro runtime notes.

## Findings

- The engine intentionally does not synthesize audio yet because the local Kokoro repo has PyTorch assets only.
- No Apple Foundation Models, `SystemLanguageModel`, `FoundationModels`, `AVSpeechSynthesizer`, or fake audio fallback is present in the Kokoro boundary.
- The default voice is `af_heart`.
- Voice picker data is embedded from Kokoro voice names in local `VOICES.md` and `voices/*.pt`.
- License bundling is not complete because the local checkout has README frontmatter declaring Apache-2.0 but no standalone `LICENSE` file.

## Fixes applied

- Added typed `KokoroEngineError.nativeRuntimeUnavailable(.pythonPyTorchOnly)` so the sender UI can surface the blocker without pretending playback succeeded.
- Kept `KokoroEngine.defaultVoiceID`, `KokoroEngine.voices`, and `availableVoices` for the current sender UI.
- Added the requested direct API: `synthesize(text:voice:speed:pitchSemitones:)`.
- Kept the current `synthesize(_ request:)` adapter so `SenderViewModel` does not need a cross-agent edit.
- Added validation for empty script, unknown voice, speed, and pitch before the runtime blocker.

## Build note

The requested simulator build was attempted. The initial sandboxed run could not access CoreSimulatorService, `~/.cache/clang`, or SwiftPM manifest caches. The escalated build reached the app target but failed before Kokoro validation because `ContentView.swift` references `SplashView` and `DevToolsRootView`, which are present as new untracked files but are not yet in the generated Xcode project used by the build. I did not regenerate `TCCC_IOS.xcodeproj` because that is outside Agent B's write scope.
