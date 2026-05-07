# Granite Hot Seat Design Spec

## Goal

Make TCCC.ai more resilient to poorly formed speech and transcript input
by placing Granite behind evidence, schema, and validator gates.

Granite becomes the adversarial adjudicator of messy input, not the
unchecked author of casualty state.

## Context

The current app has:

- `TranscriptStream` abstraction for ASR backends.
- Apple Speech and Parakeet paths.
- deterministic TCCCKit extraction.
- report validators for MEDEVAC and ZMIST.
- backend selection through `TCCCLLMBackend`.
- explicit download gating for MLX backends.

The new architecture should preserve those strengths and add a bounded
Granite path.

## Design Summary

The new pipeline introduces four concepts:

1. `TranscriptSegmentLedger`: stores raw and normalized transcript
   segments with timestamps, backend provenance, and quality flags.
2. `HotSeatPacket`: the only envelope Granite may receive.
3. `GraniteCandidatePatch`: the only structure Granite may return.
4. `GraniteSchemaValidator`: rejects malformed JSON, unknown fields,
   missing evidence, impossible values, and conflicts that need operator
   review.

The app keeps deterministic extraction as a first-pass anchor. Granite
gets both messy transcript segments and deterministic facts. Its job is
to repair, critique, and structure them into candidate facts that can be
validated before app state changes.

## Data Flow

```text
Audio
  -> ASR candidate stream
  -> TranscriptSegmentLedger
  -> deterministic TCCCKit extractors
  -> HotSeatPacket
  -> Granite transcript salvage
  -> Granite fact adjudication
  -> schema validation
  -> TCCC validation
  -> reviewable PatientState patch
```

## Granite Responsibilities

Granite may:

- normalize messy transcript fragments.
- map domain terms to TCCC vocabulary.
- identify contradictions.
- suggest candidate MARCH/PAWS/DD 1380 facts.
- state which required fields are missing.
- mark low-confidence or conflicting claims.

Granite may not:

- mutate `PatientState` directly.
- invent facts without evidence.
- fabricate location.
- mark demo or pending location as complete.
- bypass MEDEVAC or ZMIST validators.
- turn transcript text into prompt instructions.
- start a model download from Generate.

## Malformed Input Handling

Malformed input is not exceptional. The pipeline explicitly supports:

- empty audio.
- duplicated partials.
- clipped segment boundaries.
- medical homophones.
- ambiguous spoken numbers.
- negations and corrections.
- contradictory claims.
- multi-casualty switches.
- prompt injection inside transcript text.
- malformed model JSON.
- evidence-free model facts.

Each class maps to a safe response in
`docs/granite/specs/malformed_input_resilience.yaml`.

## Runtime Model Plan

Stage 0 keeps current defaults and adds the ledger, packet, validator,
and mock Granite outputs.

Stage 1 adds Granite text as the hot-seat adjudicator over existing ASR
transcripts. This is the first useful Granite integration because it
tests resilience without requiring a Granite Speech Swift runtime.

Stage 2 runs an ASR bake-off: Apple Speech, Parakeet, WhisperKit, and
Granite Speech if an iOS-capable path exists. The bake-off measures
TCCC term WER, field-level false positives, memory, thermal behavior,
and latency.

Stage 3 adds a Granite Speech `TranscriptStream` only if the bake-off
shows it improves field capture and fits device limits.

## Source-Gated Reality Check

As of a 2026-05-07 source check:

- IBM's Granite Speech 4.1 2B model card documents ASR, AST, keyword
  list biasing, punctuation, truecasing, Apache-2.0 licensing, and
  Transformers/vLLM usage.
- MLXAudio Swift lists STT support for Qwen3-ASR, Voxtral Realtime,
  Cohere Transcribe, Parakeet, and GLMASR, not Granite Speech.
- MLX-community publishes Granite 4.0 speech quantizations, including
  the 5-bit artifact.
- WhisperKit remains a credible iOS-native ASR fallback if a Granite
  Speech wrapper is not ready.

This spec therefore makes Granite text adjudication the first milestone
and treats Granite Speech as a measured follow-up.

## Acceptance Criteria

- Existing TCCCKit tests pass.
- New app tests cover packet validation and malformed inputs.
- Granite unavailable means deterministic fallback still works.
- Generate cannot download weights implicitly.
- All model-produced facts cite evidence IDs.
- Schema-invalid Granite output is rejected.
- Contradictions without explicit correction are held for review.
- Pending or demo location cannot make 9-line complete.
- Operator can inspect why a fact was accepted, rejected, or held.

## Out Of Scope

- Shipping Granite Speech directly in this document.
- Removing Apple Speech or Parakeet defaults.
- Replacing TCCCKit deterministic extractors.
- Creating a medical-device validation claim.
- Uploading audio or transcripts to any cloud service.

