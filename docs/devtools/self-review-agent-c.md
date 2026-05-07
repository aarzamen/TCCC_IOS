# Agent C Self Review

## Scope

Implemented the Sender compose state model, compose UI, and ambient dBFS meter only. I did not wire app navigation or commit changes.

## Critique And Fixes

- Issue: `KokoroEngine.swift` is owned by Agent B and is not present in this checkout, so a direct dependency would make Agent C fail before merge.
  Fix: `SenderViewModel` accepts a Kokoro-only synthesis closure and defaults to a `nativeRuntimeUnavailable` error. It does not call Apple Speech, generate fake audio, or hide the runtime blocker.
- Issue: Ambient mic UI can easily imply environmental sound pressure.
  Fix: the meter labels the reading as `dBFS` and computes RMS full-scale amplitude from the input tap rather than dB SPL.
- Issue: Leaving the compose page or tapping Send/Play could leave the input tap active.
  Fix: `SenderComposeView` stops `AmbientMeter` on disappear and immediately before sending.
- Issue: Sliders and the voice picker need gloved-hand affordance.
  Fix: controls use the existing `Layout.minHitTarget` and `BigButton` patterns with palette-driven styling.

## Integration Notes

- The orchestrator or Agent B should bridge the view model's `SynthesisHandler` to `KokoroEngine.synthesize`, mapping `SenderSynthesisRequest` into `KokoroSynthesisRequest`.
- `SenderReadoutState` preserves the script and any synthesis error so Agent D can show readout text even while Kokoro native conversion remains unavailable.

## Verification

- Ran the requested iPhone 15 Pro simulator build in a temp regenerated copy at `/private/tmp/tccc_ios_devtools_agent_c_src` with DerivedData `/private/tmp/tccc_ios_devtools_agent_c`.
- Initial sandboxed build was blocked by Xcode cache and CoreSimulator access. The escalated build reached the app target.
- The temp copy briefly failed on a concurrent Agent A file (`DevToolsLandingView.swift`) while the shared worktree kept moving.
- Final verification from the actual shared worktree succeeded:
  `xcodebuild -quiet -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=F9D1EDB3-0711-4935-8A78-F720F85F09DE -configuration Debug -derivedDataPath /private/tmp/tccc_ios_devtools_agent_c build CODE_SIGNING_ALLOWED=NO -skipMacroValidation`.
- Build warnings remain outside Agent C scope: `UIRequiresFullScreen` deprecation, `Haptics` exhaustive switch cases, and existing `ParakeetTranscriptStream` concurrency/unused-value warnings.
