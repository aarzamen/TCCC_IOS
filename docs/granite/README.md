# Granite Hot Seat Planning Bundle

This folder describes the Granite-centered processing path for TCCC.ai.
Sprint 1 and the first Sprint 2 slices now have code behind them; the
documents remain the handoff pack and safety contract for the next
agent or developer session.

## Why This Exists

The app already has a strong deterministic extraction core, report
validators, and DD 1380-oriented UI. The weaker seam is not one missing
model. The weaker seam is how messy speech becomes trusted structure.

The Granite hot-seat design moves all model output behind evidence,
schema, and validation gates:

1. Audio and ASR produce timestamped transcript segments.
2. Deterministic extractors produce first-pass TCCC facts.
3. Granite receives an evidence packet and is asked to challenge, repair,
   and structure the messy input.
4. Schema validators and TCCC validators decide what can enter app state.
5. Anything uncertain remains reviewable, pending, or rejected.

Granite is therefore central, but not trusted blindly.

## Files

- `SPRINT_CONTEXT.md`
  - Compact resumption note for this sprint after context compaction.
- `SPRINT_BOARD.yaml`
  - Machine-readable task board, acceptance gates, and verification
    commands for the first implementation slice.
- `GRANITE_HOT_SEAT_ARCHETYPE.md`
  - The larger architecture and migration plan.
- `INSTRUCTIONS_FOR_AGENTS.md`
  - How future agents should implement this without breaking RF discipline
    or the existing Apple/Parakeet defaults.
- `specs/granite_pipeline_contract.yaml`
  - Machine-readable stage contract for the new pipeline.
- `specs/malformed_input_resilience.yaml`
  - Malformed-input taxonomy and required handling.
- `specs/tccc_granite_keywords.yaml`
  - TCCC keyword groups for Granite keyword biasing and transcript cleanup.
- `specs/asr_bakeoff_protocol.yaml`
  - Local-only ASR comparison protocol for Apple Speech, Parakeet,
    WhisperKit, and Granite Speech when available.
- `specs/device_profile_protocol.yaml`
  - iPhone profiling metrics and fallback thresholds for Granite text
    hot-seat review.
- `specs/report_critique_contract.yaml`
  - Schema and validator rules for critique-only report review.
- `../superpowers/specs/2026-05-07-granite-hot-seat-design.md`
  - Narrative design spec.
- `../superpowers/plans/2026-05-07-granite-hot-seat.md`
  - Step-by-step implementation plan.

## Current Source Check

Checked on 2026-05-07:

- IBM publishes `ibm-granite/granite-speech-4.1-2b` as an Apache-2.0
  speech model with keyword list biasing, punctuation, truecasing, ASR,
  and AST support.
- `Blaizzy/mlx-audio-swift` lists STT models such as Qwen3-ASR,
  Voxtral Realtime, Cohere Transcribe, Parakeet, and GLMASR, but not a
  Granite Speech Swift model class.
- `mlx-community/granite-4.0-1b-speech-5bit` exists as an MLX artifact
  around 2.23 GB, and the Hugging Face model index also shows 4-bit,
  5-bit, 6-bit, 8-bit, BF16, and MXFP4 Granite 4.0 speech variants.
- `mlx-community/granite-4.0-h-1b-base-4bit` exists as the text hot-seat
  backend target. It remains explicit-download only in Settings.
- WhisperKit remains the proven iOS-native ASR fallback path if Granite
  Speech cannot be made reliable on device quickly.

Source links:

- [Blaizzy/mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift)
- [ibm-granite/granite-speech-4.1-2b](https://huggingface.co/ibm-granite/granite-speech-4.1-2b)
- [mlx-community/granite-4.0-1b-speech-5bit](https://huggingface.co/mlx-community/granite-4.0-1b-speech-5bit/tree/main)
- [mlx-community/granite-4.0-h-1b-base-4bit](https://huggingface.co/mlx-community/granite-4.0-h-1b-base-4bit/tree/main)
- [Hugging Face granite_speech model index](https://huggingface.co/models?other=granite_speech)
- [WhisperKit paper](https://arxiv.org/abs/2507.10860)

## Non-Negotiables

- No runtime network for care delivery.
- No cloud inference.
- No model auto-download from Generate buttons.
- No model-generated fact enters app state without evidence IDs.
- No generated report bypasses deterministic validators.
- Unknown is a valid output. Fabrication is not.
