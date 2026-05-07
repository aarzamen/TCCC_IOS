# Granite Hot Seat Sprint Context

Updated: 2026-05-07

This file is the compact resumption point for the Granite hot-seat sprint.
If the thread compacts, start here, then open the implementation plan.

## Sprint Goal

Build the first Granite-centered processing path that makes TCCC.ai more
resilient to malformed speech input while preserving the existing safety
boundary:

- deterministic TCCCKit extraction remains the first pass.
- Granite adjudicates bounded evidence packets.
- validators decide what can mutate app state.
- low-confidence or conflicting output becomes reviewable, not trusted.

## Start Here

1. Read `docs/granite/README.md`.
2. Read `docs/granite/SPRINT_BOARD.yaml`.
3. Execute `docs/superpowers/plans/2026-05-07-granite-hot-seat.md`
   task by task.
4. Use `docs/granite/INSTRUCTIONS_FOR_AGENTS.md` as the guardrail file
   before every Granite-related edit.

## Current Repo State At Sprint Setup

The sprint setup was created in the worktree:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS
```

Important existing changes in the worktree include the review-hardening
fixes for 9-line completion, transmit gating, backend preflight, and
stale build docs. Those are not Granite runtime code, but they are part of
the current working diff and should not be reverted.

The Granite sprint setup adds only docs and specs:

- `RESEARCH_GRANITE_SPEECH.md`
- `docs/granite/README.md`
- `docs/granite/GRANITE_HOT_SEAT_ARCHETYPE.md`
- `docs/granite/INSTRUCTIONS_FOR_AGENTS.md`
- `docs/granite/SPRINT_CONTEXT.md`
- `docs/granite/SPRINT_BOARD.yaml`
- `docs/granite/specs/granite_pipeline_contract.yaml`
- `docs/granite/specs/malformed_input_resilience.yaml`
- `docs/granite/specs/tccc_granite_keywords.yaml`
- `docs/superpowers/specs/2026-05-07-granite-hot-seat-design.md`
- `docs/superpowers/plans/2026-05-07-granite-hot-seat.md`

## First Coding Slice

The first implementation slice should be deliberately small:

1. Add `TranscriptSegmentLedger`.
2. Add tests for duplicate partial collapse and transcript prompt-injection
   marking.
3. Add `HotSeatPacket` and packet builder.
4. Add `GraniteSchemaValidator` with a mock patch type.
5. Wire no model yet.

Do not start by adding MLX, WhisperKit, or Granite Speech weights. The
hot-seat contract has to exist before a model can safely sit behind it.

## Non-Negotiables

- No runtime cloud inference.
- No model download from Generate buttons.
- No direct model-to-`PatientState` mutation.
- No evidence-free candidate fact acceptance.
- No transcript text treated as instructions.
- No pending, demo, or missing location counted as transmit-ready.
- Apple Foundation and Apple Speech remain the operational defaults until
  an alternate path is field-validated.

## Verification Commands

Use these exact commands for the sprint unless a task narrows the scope:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS
xcodegen generate
xcodebuild test -project TCCC_IOS.xcodeproj -scheme TCCC_IOS \
  -destination 'id=DE7116A4-74E0-40EA-85C2-0D19C290BD0E' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation
```

For TCCCKit-only changes:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS/Packages/TCCCKit
swift test
```

For docs/spec hygiene:

```bash
cd /Users/ama/.codex/worktrees/b727/TCCC_IOS
ruby -ryaml -e 'ARGV.each { |path| YAML.load_file(path); puts "#{path}: ok" }' docs/granite/specs/*.yaml docs/granite/SPRINT_BOARD.yaml
git diff --check
```

## Done For Sprint 1

Sprint 1 is done when:

- transcript evidence is stored as segments with timestamps and quality
  flags.
- duplicate ASR partials are collapsed before Granite receives input.
- transcript instruction-like content is flagged as content, not obeyed.
- a bounded `HotSeatPacket` can be built from transcript evidence and
  deterministic facts.
- a candidate Granite patch can be rejected for missing evidence, unknown
  fields, unknown evidence IDs, or impossible values.
- no real Granite model dependency is required for the tests.

## Deferred Until After Sprint 1

- Real Granite text model integration.
- Grammar-constrained generation.
- Granite Speech ASR wrapper.
- WhisperKit bake-off.
- Device memory and thermal profiling.
- Report-level Granite critique.

