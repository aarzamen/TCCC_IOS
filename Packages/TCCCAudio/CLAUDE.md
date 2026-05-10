# TCCCAudio (Sprint 1 — Granite Speech Foundation)

Local shim package bringing `Blaizzy/mlx-audio-swift` into the app
target with the heavy MLX deps isolated here, not in `Packages/TCCCKit`
(pure logic) and not in the app target (AGENTS.md "no logic in app
target"). Mirrors the existing `Packages/TCCCLLM` shim pattern.

## Pinned versions

| Dep | Version | SHA |
|---|---|---|
| `mlx-audio-swift` | v0.1.2 | `fcbd04daa1bfebe881932f630af2ba6ce9af3274` |

Resolved via `git ls-remote https://github.com/Blaizzy/mlx-audio-swift refs/tags/v0.1.2`.

## Resolver-conflict notes (G0)

v3 §G0 anticipated a conflict between this package's `mlx-swift-lm` ≥ 3.x
need and `Packages/TCCCLLM`'s `from: "2.25.5"`. **The conflict did not
fire** — mlx-audio-swift v0.1.2 actually declares
`.upToNextMajor(from: "2.30.3")` on `mlx-swift-lm`, which means
`>= 2.30.3, < 3.0.0`. That intersects cleanly with TCCCLLM's
`from: "2.25.5"` (also `< 3.0.0`). The resolver picks whatever 2.x is
latest and both sides accept it. No Path A/B/C recovery needed.

## Sprint 1 phase journal

### G0 — Scaffolding (2026-05-10)

- Created `Packages/TCCCAudio/` mirroring `Packages/TCCCLLM/`.
- Pinned mlx-audio-swift to commit SHA, not a branch.
- Re-export `MLXAudioCore` + `MLXAudioSTT` only. `MLXAudioCodecs`,
  `MLXAudioVAD`, etc. are not needed for Sprint 1's ASR work.
- Did not touch `TCCC_IOS/Audio/GraniteSpeechTranscriptStream.swift`
  body in G0 per v3 §G0 explicit constraint. G1 fills in the body.

### `swift test` from CLI: not the right harness

v3 §G0.6 lists `cd Packages/TCCC<X> && swift test` as part of
verification. It doesn't work for the MLX-dependent packages and
never has — both `TCCCLLM` and `TCCCAudio` declare `.iOS(.v17)` only,
but `swift test` defaults to the host (macOS), and the upstream
products require macOS 14:

```
error: the library 'TCCCAudio' requires macos 10.13, but depends on
the product 'MLXAudioCore' which requires macos 14.0; consider
changing the library 'TCCCAudio' to require macos 14.0 or later, or
the product 'MLXAudioCore' to require macos 10.13 or earlier.
```

`TCCCKit` is pure logic and `swift test` works there (724 tests
passing on host). For `TCCCLLM` and `TCCCAudio`, the canonical
verification is the xcodebuild simulator build (which passed cleanly
in G0) and `xcodebuild test` on the iPhone 17 Pro simulator (which
G1 will exercise once test targets land). Don't add `.macOS(.v14)`
to TCCCAudio just to make `swift test` quiet — it has no test target
yet, and once G1 lands tests, they'll run through the simulator the
same way TCCC_IOSTests does today.

### Destination-string note (matches `SPRINT_BOARD.yaml` precedent)

The v3 spec's verification command uses
`-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26'`. On
this machine that's ambiguous — both an iOS 26.3 and iOS 26.4
iPhone 17 Pro simulator are available, and `OS=26` matches neither
because xcodebuild expects an exact runtime version. The fix is to
pin by UUID, matching what Codex's earlier sprint already used in
`docs/granite/SPRINT_BOARD.yaml`:

```
-destination 'platform=iOS Simulator,id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E'
```

That's the iOS 26.4 iPhone 17 Pro simulator. Use this form for all
autonomous self-verification builds. If the sim ID drifts on a fresh
machine, run `xcrun simctl list devices iPhone | grep "iPhone 17 Pro"`
to find the current ID.

### Loader API surface at the pinned SHA (note for G2)

At v0.1.2 (`fcbd04daa1bfebe881932f630af2ba6ce9af3274`),
`MLXAudioSTT.GraniteSpeechModel` exposes only one loader:

```swift
public static func fromPretrained(
    _ modelPath: String,        // HF repo ID, e.g. "mlx-community/granite-4.0-1b-speech-5bit"
    cache: HubCache = .default
) async throws -> GraniteSpeechModel
```

The loader internally calls `ModelUtils.resolveOrDownloadModel(repoID:requiredExtension:cache:)`.
A `fromModelDirectory(URL)` overload exists on `main` (line 1080) but
**was added after v0.1.2** — not available at our pin.

**Implication for G2:** the resolver seeds an `HubCache` whose root is
the user-picked Files.app folder. If the folder already contains an HF
snapshot layout (`models--<owner>--<repo>/snapshots/<rev>/...`),
`resolveOrDownloadModel` returns the existing path with no download.
This matches v3 §2's "Loader API contract" caveat exactly. Documented
here so G2 doesn't re-discover it.

(G1, G2, G3, G4 sections will be appended as those phases land.)
