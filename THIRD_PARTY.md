# Third-party code, weights and forms

TCCC.ai iOS is MIT-licensed (see [LICENSE](LICENSE)). This file lists what a
build pulls in from elsewhere and the terms that come with it. Versions are the
pins in `TCCC_IOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
and `Packages/*/Package.resolved`; the licence of each package was read from its
`LICENSE` file at that pinned revision on 2026-11-05. Nothing here is vendored
into the repository: SwiftPM fetches the packages at build time, and no model
weights are tracked (`*.safetensors` is ignored).

"v1.0" below refers to [docs/SCOPE.md](docs/SCOPE.md), which removes the
alternative speech and language backends. Until that removal lands, the
manifests still declare every package in the first table.

## Swift packages (SwiftPM)

| Package | Pinned | Licence | Used for | v1.0 |
|---|---|---|---|---|
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.3 | MIT | Array runtime for on-device models | stays (Qwen3-ASR) |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 2.31.3 | MIT | Model loading / tokenizer plumbing | stays |
| [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | fcbd04d (v0.1.2) | MIT | Speech models, including Qwen3-ASR | stays |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 1.2.1 | Apache-2.0 | Tokenizers, model configs | stays |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | 0.9.0 | Apache-2.0 | Hub file layout (transitive) | stays |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 2.3.5 | Apache-2.0 | Chat templates (transitive) | stays |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 0.14.4 | Apache-2.0 | Parakeet speech backend, Kokoro TTS in DevTools | leaves |
| [AnyLanguageModel](https://github.com/huggingface/AnyLanguageModel) | 0.8.0 | MIT | LFM2 / Qwen 3 language-model backends (via `Packages/TCCCLLM`) | leaves |
| [EventSource](https://github.com/mattt/EventSource) | 1.4.1 | MIT | transitive (AnyLanguageModel) | leaves |
| [JSONSchema](https://github.com/mattt/JSONSchema) | 1.3.1 | MIT | transitive (AnyLanguageModel) | leaves |
| [PartialJSONDecoder](https://github.com/mattt/PartialJSONDecoder) | 1.0.0 | Apache-2.0 | transitive (AnyLanguageModel) | leaves |
| [yyjson](https://github.com/ibireme/yyjson) | 0.12.0 | MIT | transitive JSON parser | depends on resolution |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 600.0.1 | Apache-2.0 with Runtime Library Exception | Swift macros (AnyLanguageModel) | leaves |
| [swift-nio](https://github.com/apple/swift-nio), [swift-crypto](https://github.com/apple/swift-crypto), [swift-asn1](https://github.com/apple/swift-asn1), [swift-collections](https://github.com/apple/swift-collections), [swift-atomics](https://github.com/apple/swift-atomics), [swift-numerics](https://github.com/apple/swift-numerics), [swift-system](https://github.com/apple/swift-system) | see Package.resolved | Apache-2.0 | transitive (Apple) | depends on resolution |

Apache-2.0 asks a binary distribution to carry the licence text and any
`NOTICE` file of the packages it includes (swift-nio, swift-crypto and
swift-asn1 ship one). An App Store or TestFlight build should bundle them;
`scripts/` does not do this yet.

## Model weights

No weights are in this repository. The build embeds a privately staged pack
(`tools/embed_offline_models.sh`) or the app downloads them on an explicit
operator action. Licences as published on the Hugging Face Hub, read 2026-11-05.

| Weights | Licence | v1.0 |
|---|---|---|
| [Qwen/Qwen3-ASR-0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B) and the MLX conversions [mlx-community/Qwen3-ASR-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit) / [-8bit](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit) | Apache-2.0 | planned speech option |
| [mlx-community/granite-4.0-1b-speech-5bit](https://huggingface.co/mlx-community/granite-4.0-1b-speech-5bit) (IBM Granite Speech) | Apache-2.0 | leaves |
| [mlx-community/granite-4.0-h-1b-base-4bit](https://huggingface.co/mlx-community/granite-4.0-h-1b-base-4bit) (Granite text, hot-seat review) | Apache-2.0 | leaves |
| [mlx-community/Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit) | Apache-2.0 | leaves |
| [mlx-community/LFM2-1.2B-4bit](https://huggingface.co/mlx-community/LFM2-1.2B-4bit) (Liquid AI) | "other": LFM Open License v1.0 | leaves |
| [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) (NVIDIA base model) | "other" on the Hub; read the model card before shipping | leaves |
| [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) (DevTools text-to-speech only) | Apache-2.0 | DevTools only |

Apple Speech and Apple Foundation Models are system frameworks covered by the
iOS SDK terms, not by any of the above.

## US government works

- **DD Form 1380, Tactical Combat Casualty Care (TCCC) Card, JUL 2025.** A
  United States Department of Defense form. Works of the US government are not
  subject to copyright in the United States (17 U.S.C. § 105). The bundled
  template `TCCC_IOS/Resources/DD1380/DD1380_JUL2025_template.pdf` is the
  official PDF with its damaged encryption repaired and its fields renamed
  (`tools/repair_dd1380_jul2025.py`, `tools/prepare_dd1380_template.py`); the
  drawing and fonts are the official ones.
- **TCCC Guidelines and DD 1380 field inventory extracts** in
  `reference/rubric/extracted/` are taken verbatim from Joint Trauma System /
  Committee on TCCC publications, also US government works.

## Tool-only dependencies (never shipped)

`tools/prepare_dd1380_template.py` and `tools/repair_dd1380_jul2025.py` run
with `pypdf` (BSD-3-Clause) and `cryptography` (Apache-2.0 / BSD-3-Clause)
through `uv run --with`; neither is part of the app.

## Test fixtures

`TCCC_IOS/Resources/test_5min.wav` and the scenario texts under
`Packages/TCCCKit/Tests/TCCCExtractorTests/Resources/scenarios/` are authored
fictional scripts, rendered with text-to-speech where audio is needed. They
contain no real casualty data.
