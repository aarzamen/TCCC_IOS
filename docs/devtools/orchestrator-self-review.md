# Orchestrator Self-Review

## Scope

- Integrated the splash route, DevTools sender/receiver navigation, Kokoro-only engine boundary, sender compose page, ambient meter, readout page, and playback visualizer.
- Regenerated `TCCC_IOS.xcodeproj` so the new Swift files are part of the app target.
- Verified against the user-assigned iPhone 15 lane, not the iPhone 17 lane.

## Findings

- The existing casualty-management app remains behind the `TCCC.ai` splash action through `MainAppShell`.
- DevTools Sender now routes to `SenderPlaybackView`; Receiver stays a static placeholder with no networking or capture work.
- The sender UI can accept pasted text, update word count and estimated reading time, meter ambient input at roughly 10 Hz, and move to readout after Send/Play.
- The original Kokoro clone remains PyTorch-only, but the user broadened the requirement to any working local TTS engine. Sender now renders a real WAV on device through iOS speech synthesis and plays that file through `AVAudioPlayer`.
- Readout uses preserved script text, sentence-level timing metadata, and `AVAudioPlayer` metering from the rendered audio URL. It does not fake playback levels.

## Critique And Fixes

- Issue: worker lanes temporarily disagreed about whether Sender was enabled.
  Fix: integrated `DevToolsRootView` with a real `.sender` route and passed `onOpenSender` into `DevToolsLandingView`.
- Issue: the first integrated build exposed SwiftUI `frame` argument ordering in new card views.
  Fix: reordered `minHeight` before `maxHeight` in the affected cards and rebuilt.
- Issue: acceptance criteria originally required native Kokoro playback, but the available Kokoro clone is PyTorch-only.
  Fix: after user approval to use any TTS engine, wired the iPhone-compatible speech renderer. It writes a real WAV, maps speed and pitch into the rendered utterance, and preserves the existing metered playback pipeline.
- Issue: the original spec requested simulator validation, but the user later assigned Codex to the plugged-in iPhone 15.
  Fix: used `Default15` / `00008130-000E78E210FA8D3A` for the integrated device build and left the iPhone 17 identifiers alone.

## Verification

- iPhone 15 physical-destination build passed:
  `xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=00008130-000E78E210FA8D3A -configuration Debug -derivedDataPath /private/tmp/tccc_ios_device_build build CODE_SIGNING_ALLOWED=NO -skipMacroValidation`
- iPhone 15 signed Debug build passed:
  `xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=00008130-000E78E210FA8D3A -configuration Debug -derivedDataPath /private/tmp/tccc_ios_device_signed build -skipMacroValidation`
- Installed the signed build on `Default15`:
  `xcrun devicectl device install app --device DF20767D-0672-56DB-9928-AD2191C2CCA5 /private/tmp/tccc_ios_device_signed/Build/Products/Debug-iphoneos/TCCC_IOS.app`
- Launched the installed app on `Default15`:
  `xcrun devicectl device process launch --device DF20767D-0672-56DB-9928-AD2191C2CCA5 --terminate-existing --json-output /private/tmp/tccc_ios_iphone15_launch.json com.aarzamen.TCCCai`
- Launch JSON reported success with process identifier `4036`.
- TCCCKit package tests passed:
  `swift test` from `Packages/TCCCKit` - 724 tests, 0 failures.
- Focused iPhone 15 TTS tests passed:
  `xcodebuild -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -destination id=00008130-000E78E210FA8D3A -configuration Debug -derivedDataPath /private/tmp/tccc_ios_kokoro_red test -only-testing:TCCC_IOSTests/KokoroEngineTests -skipMacroValidation`
- Device inventory confirms `Default15` is an available paired iPhone 15 Pro and `Aaron's iPhone` is the separate iPhone 17 Pro lane.

## Remaining Gaps

- The active sender path is device speech TTS, not native Kokoro model inference. Native Kokoro still requires conversion or a bundleable Core ML / MLX Swift path.
- No third-party license bundle can be completed from the current local clone because it lacks a standalone Apache-2.0 `LICENSE` file.
- Automated on-device tap-walk is still unverified. Device tooling confirmed install and launch, but did not visually assert splash, DevTools, Sender, Receiver, or button transitions.
