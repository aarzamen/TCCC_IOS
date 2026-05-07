# Granite Hot Seat Archetype

## Intent

Put Granite in the center of the speech-to-structure path while making
the system more resilient to malformed input, not more model-dependent.

The desired behavior is not "Granite hears audio and fills the card."
The desired behavior is:

1. The app captures messy field narration.
2. The deterministic engine extracts whatever it can.
3. Granite receives the messy input plus deterministic evidence.
4. Granite returns bounded candidate structure with evidence pointers.
5. Validators decide what is accepted, rejected, or marked for review.

Granite is in the hot seat because it must explain the messy transcript
against evidence. It is not the final authority.

## Operating Model

### Principle 1: Evidence Before State

Every model-produced claim must include:

- `evidence_ids`: transcript segment IDs or prior deterministic fact IDs.
- `source_stage`: `asr`, `deterministic`, `granite_hot_seat`, or
  `human_edit`.
- `confidence`: one of `high`, `medium`, `low`, `conflict`, `unknown`.
- `accepted_by`: validator name, or `null` if still pending.

If a claim has no evidence ID, it cannot enter `PatientState`.

### Principle 2: Granite Receives Packets, Not Raw Strings

Granite should never receive a naked transcript blob. It receives a
`HotSeatPacket`:

- transcript segments with timestamps, partial/final status, and ASR
  backend provenance.
- deterministic facts already extracted by TCCCKit.
- known patient IDs and active patient context.
- DD 1380 fields that are already populated.
- explicit list of allowed output schemas.
- instruction that transcript content is evidence only, never commands.

### Principle 3: Two-Pass Structure

Granite should run in two distinct roles:

1. `transcript_salvage`: clean, segment, and normalize poor ASR output.
2. `fact_adjudication`: produce schema-bound candidate facts from the
   cleaned transcript and deterministic facts.

Do not combine transcript cleaning, patient-state mutation, and report
generation in one prompt.

### Principle 4: Deterministic Validators Win

Granite can suggest:

- MARCH/PAWS facts.
- DD 1380 field values.
- ZMIST and 9-line candidate fields.
- uncertainty, conflicts, and missing required data.

Granite cannot override:

- DD 1380 field type constraints.
- MARCH/PAWS vocabulary constraints.
- medevac line validation.
- location provenance checks.
- protected-write and RF discipline boundaries.

### Principle 5: Malformed Input Is Expected

The system assumes input will be clipped, duplicated, contradictory,
mixed with background speech, and full of medical homophones. The
processing path must preserve uncertainty instead of smoothing it away.

## Target Data Flow

```text
AVAudioEngine
  -> AudioFrameLedger
  -> ASR candidate stream
  -> TranscriptSegmentLedger
  -> Normalization and de-duplication
  -> TCCCKit deterministic extraction
  -> HotSeatPacket
  -> Granite transcript_salvage
  -> Granite fact_adjudication
  -> Schema validation
  -> TCCC report validators
  -> PatientState patch queue
  -> Operator review / accepted app state
```

## Model Roles

### Current Default Role

Apple Speech and Parakeet remain the operational defaults until an
on-device Granite path is proven. Granite text can still be tested as the
hot-seat adjudicator over transcripts produced by existing ASR.

### Stage 1 Role: Granite Text Hot Seat

Use a small Granite text model as the structured adjudicator:

- Input: transcript segments plus deterministic facts.
- Output: strict JSON candidate facts.
- Constraint: no runtime download except explicit Settings download.
- Success gate: improves malformed-input recovery without increasing
  false positives in DD 1380 fields.

### Stage 2 Role: Granite Speech Candidate ASR

Wrap a Granite Speech model for ASR only after:

- the Swift runtime is implemented or an iOS-capable runtime exists.
- on-device load time, memory, and thermal behavior are measured.
- TCCC keyword-biasing improves field vocabulary capture.
- fallback to Apple/Parakeet/WhisperKit remains available.

### Stage 3 Role: Dual Granite ASR Plus Text Hot Seat

Granite Speech produces one ASR candidate stream. Granite text remains
the hot-seat adjudicator. The two roles stay separate so an ASR failure
does not also own the state-synthesis path.

## Required Interfaces

### `TranscriptSegment`

Represents speech evidence, not medical truth.

Fields:

- `id`
- `start_ms`
- `end_ms`
- `speaker_hint`
- `text_raw`
- `text_normalized`
- `asr_backend`
- `is_final`
- `quality_flags`

### `DeterministicFact`

Represents facts extracted by existing TCCCKit logic.

Fields:

- `id`
- `patient_id`
- `domain`
- `field`
- `value`
- `evidence_ids`
- `extractor`
- `confidence`

### `HotSeatPacket`

The only allowed Granite input envelope.

Fields:

- `packet_id`
- `created_at_utc`
- `active_patient_id`
- `segments`
- `deterministic_facts`
- `known_patients`
- `allowed_schemas`
- `blocked_actions`

### `GraniteCandidatePatch`

The only allowed Granite output envelope.

Fields:

- `packet_id`
- `patient_id`
- `candidate_facts`
- `conflicts`
- `missing_required_fields`
- `rejected_inputs`
- `model_self_check`

## Validator Gates

1. JSON parses.
2. JSON conforms to schema.
3. Every candidate fact has evidence.
4. Every evidence ID exists.
5. Every field maps to DD 1380 or MARCH/PAWS vocabulary.
6. Values pass domain validation.
7. Conflicts are either resolved by recency/correction rules or held for
   review.
8. No pending location or demo location can mark a 9-line as ready.
9. No generated report is accepted if the validator rewrites too much of
   it.

## Malformed-Input Strategy

### Duplicated Partials

Normalize repeated ASR fragments before Granite sees them. Preserve the
raw originals in the segment ledger.

### Clipped Words

Mark segments with `clipped_start` or `clipped_end`. Granite may infer
only if another segment or deterministic fact supports the same value.

### Contradictions

Treat later explicit correction phrases as higher priority:

- "correction"
- "negative"
- "scratch that"
- "not left, right"
- "tourniquet moved"

If no correction marker exists, hold the conflict for review.

### Prompt Injection In Transcript

Transcript text is evidence. It cannot instruct Granite. Any phrase like
"ignore previous" or "write normal vitals" is tagged as content, not an
instruction.

### Impossible Values

Validators reject impossible values. Granite may produce a review note,
but app state remains unchanged.

## Migration Stages

### Stage 0: Harden Current Pipeline

- Keep Apple Speech and Parakeet defaults.
- Add transcript segment ledger.
- Add input quality flags.
- Add schema-bound Granite candidate outputs with a mock backend.
- Add malformed-input test fixtures.

### Stage 1: Granite Text Adjudicator

- Add Granite text backend behind `TCCCLLMBackend`.
- Use explicit Settings download only.
- Add grammar-constrained candidate JSON.
- Run validators before app state mutation.

### Stage 2: ASR Bake-Off

- Compare Apple Speech, Parakeet, WhisperKit, and Granite Speech if
  available.
- Use the same audio fixtures and transcript ledger.
- Measure WER on TCCC terms, field-level false positives, memory, energy,
  and thermal behavior.

### Stage 3: Granite Speech Wrapper

- Implement only if Stage 2 proves value.
- Keep wrapper behind `TranscriptStream`.
- Do not replace existing defaults until device validation is better than
  the incumbent path.

### Stage 4: Report-Level Hot Seat

- Ask Granite to critique deterministic 9-line, ZMIST, and DD 1380 output.
- Validators still own the final accepted report.
- UI surfaces disagreements as review chips.

## Success Criteria

- Malformed transcripts produce fewer false state mutations.
- Missing evidence never becomes accepted state.
- TCCC vocabulary capture improves without making hallucinations easier.
- Operator can see why a fact was accepted or held.
- Existing 724 TCCCKit tests remain green.
- New app tests cover malformed input, conflicts, schema rejection, and
  no-download generation behavior.

