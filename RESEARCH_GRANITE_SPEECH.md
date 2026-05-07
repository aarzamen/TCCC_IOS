# Granite Speech For TCCC.ai

**Date:** 2026-05-07
**Target device:** iPhone 17 Pro, iOS 26.x
**Goal:** Decide how Granite should enter the TCCC.ai processing path
without weakening resilience to malformed speech, ASR, or model output.

## TL;DR

Use Granite first as a text hot-seat adjudicator over structured evidence
packets. Do not make Granite Speech the first implementation milestone.

The practical reason is simple: IBM Granite Speech 4.1 exists and has the
right ASR capabilities on paper, but the Swift/iOS runtime path is not
the same thing as a Hugging Face model card. MLXAudio Swift currently
lists Qwen3-ASR, Voxtral Realtime, Cohere Transcribe, Parakeet, and
GLMASR under `MLXAudioSTT`; it does not list a Granite Speech Swift
class. MLX-community does publish Granite 4.0 speech quantizations, but
using them in this app still requires a real Swift wrapper, device
measurement, and validator integration.

Therefore:

1. Keep Apple Speech and Parakeet as operational defaults.
2. Add a transcript/evidence ledger.
3. Add Granite text as a bounded adjudicator behind `TCCCLLMBackend`.
4. Accept only schema-valid, evidence-cited candidate facts.
5. Later run a measured ASR bake-off before choosing Granite Speech,
   WhisperKit, Parakeet, or another ASR as the preferred speech path.

## Verified Source Snapshot

### IBM Granite Speech 4.1

The `ibm-granite/granite-speech-4.1-2b` Hugging Face model card lists:

- Apache-2.0 license.
- ASR and speech translation use.
- keyword list biasing.
- punctuation and truecasing.
- plus and NAR variants.
- Transformers and vLLM usage.
- release date April 29, 2026.

This makes Granite Speech strategically relevant for TCCC vocabulary,
especially acronyms, drugs, MARCH/PAWS terms, and military shorthand.

### Swift Runtime Gap

`Blaizzy/mlx-audio-swift` describes its STT module as supporting:

- Qwen3-ASR.
- Voxtral Realtime.
- Cohere Transcribe.
- Parakeet.
- GLMASR.

Granite Speech is not listed in that Swift STT module list as of this
check. The plan should not assume a drop-in Granite Speech iOS class.

### Existing MLX Granite Artifacts

`mlx-community/granite-4.0-1b-speech-5bit` exists and is around 2.23 GB.
The Hugging Face Granite speech model index also shows Granite 4.0 speech
4-bit, 5-bit, 6-bit, 8-bit, BF16, and MXFP4 artifacts.

These artifacts are useful for a Swift wrapper effort, but they do not
remove the need to port or integrate the model class and measure iPhone
runtime behavior.

### WhisperKit Baseline

The WhisperKit paper reports an optimized on-device ASR system for Apple
devices and cites 0.46 s latency with 2.2% WER in its benchmark setting.
It also documents compression of Whisper Large v3 Turbo from 1.6 GB to
0.6 GB while preserving WER within 1% in their reported tests. This keeps
WhisperKit relevant as a proven iOS-native fallback if Granite Speech is
not ready.

## Recommended Architecture

Granite should not be treated as a monolithic replacement for the current
pipeline. It should be split into two possible roles:

### Role 1: Granite Text Hot Seat

Input:

- transcript segments.
- deterministic TCCCKit facts.
- patient context.
- allowed schemas.
- blocked actions.

Output:

- candidate facts.
- conflicts.
- missing fields.
- rejected inputs.
- self-check.

Every output fact must cite evidence IDs. Validators decide whether it
can become state.

### Role 2: Granite Speech Candidate ASR

Input:

- audio segments.
- TCCC keyword prompt.

Output:

- transcript segments with timestamps and quality flags.

This role should only ship after an on-device wrapper exists and is
measured against Apple Speech, Parakeet, and WhisperKit on the same TCCC
fixtures.

## Why The Hot Seat Comes First

Malformed-input resilience depends more on boundaries than on the ASR
model:

- Duplicate partials need de-duplication.
- Contradictions need conflict objects.
- Prompt-like phrases inside transcripts need isolation.
- Medical homophones need normalization.
- Missing evidence needs rejection.
- Report generation needs validators.

A Granite text adjudicator can improve these now using current ASR
outputs. Granite Speech can be added later without changing the evidence
and validation architecture.

## Implementation Artifacts

- `docs/granite/README.md`
- `docs/granite/GRANITE_HOT_SEAT_ARCHETYPE.md`
- `docs/granite/INSTRUCTIONS_FOR_AGENTS.md`
- `docs/granite/specs/granite_pipeline_contract.yaml`
- `docs/granite/specs/malformed_input_resilience.yaml`
- `docs/granite/specs/tccc_granite_keywords.yaml`
- `docs/superpowers/specs/2026-05-07-granite-hot-seat-design.md`
- `docs/superpowers/plans/2026-05-07-granite-hot-seat.md`

## Source Links

- [IBM Granite Speech 4.1 2B](https://huggingface.co/ibm-granite/granite-speech-4.1-2b)
- [MLXAudio Swift](https://github.com/Blaizzy/mlx-audio-swift)
- [MLX Community Granite 4.0 1B Speech 5-bit](https://huggingface.co/mlx-community/granite-4.0-1b-speech-5bit/tree/main)
- [Hugging Face granite_speech model index](https://huggingface.co/models?other=granite_speech)
- [WhisperKit paper](https://arxiv.org/abs/2507.10860)

