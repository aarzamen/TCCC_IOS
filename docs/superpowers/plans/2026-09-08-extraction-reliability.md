# Extraction reliability sprint

Authority: PROJECT_POLICY.md and the user's request to expose, assess and correct the remaining extraction failures. Codex leads integration, verification and GitHub housekeeping; native Claude owns the bounded vital-sign changes. Use systematic debugging and regression tests; one integration review.

## Evidence and scope

The exact authored valdez_alley.txt reference passes only 3/8 checks at b317975. HR remains120 instead of reassessment110; RR22 and SpO2 97 are absent; tranexamic acid and combat-gauze packing are absent. The unchanged matched-device ASR transcript passes2/8. Keep both inputs and scoring expectations unchanged.

- Native worker: VitalsExtractor.swift + VitalsNarrationTests.swift. Anchored natural-language values, latest stated reassessment, field-local negatives, non-observation controls. No normalizer/engine/scorer changes.
- Codex: CirculationExtractor.swift explicit TXA administration; PAWSExtractor.swift anatomical packing with stated material; InterventionEvidence.swift conservative positive-action clauses; InterventionNarrationTests and exact-reference control. Preserve event-log replay and clinical state ownership.
- Verify exact text reaches8/8, then replay the unchanged device text to identify genuine ASR errors separately. Run package tests, app integration, one review and device benchmark before integration/publication.

## Behavior constraints

Never infer medication or material from expected answers. Explicit drug identity must be associated with an actual administration verb. Questions, plans, conditionals, supplies and denied actions are not performed care. Unrelated negative clauses must not suppress an affirmed value/action. Preserve numeric validation. Retain source transcript and event-derived state.

One historical PAWS test narrated 'Going to irrigate' but expected performed wound care. Correct the observed false-positive contract: an affirmative irrigating example remains positive; the original planned phrase is now a negative regression. The generic PAWS wound summary remains compatible; the intervention description preserves gauze/combat-gauze only when stated.

## Integration findings and corrections

The native worker's first patch passed its 56 vital-sign tests, but integration tests exposed additional failures. Respiratory rate still required special reassessment wording; a separate RR parser bypassed the new evidence checks. Both paths now share the same parser, accept later affirmed readings without a special phrase, and refresh only rate-derived respiration labels. Independent observations such as labored breathing retain their existing precedence. A historical test asserting first-RR retention is intentionally corrected.

Integration review also reproduced false positives from nearby gauze supplies, discussing or declining an action, question marks, goals across punctuation, and long/coordinated denials. Material now requires a direct packing-with/using relationship. Questions and goals are rejected conservatively; denials do not expire after five words or reset at and/or. The legacy bare sat abbreviation retains narrow connectives so sitting up does not become an oxygen measurement. HR/RR/SpO2 range checks preserve earlier valid readings when a later candidate is invalid; BP retains its existing domain behavior.

New engine controls cover the unchanged authored reference, later capture chunks, denied readings, and replay of updated vitals/interventions. Full package: 830 tests, zero failures. One independent integration review is complete with no remaining concrete blocker. Whole-sentence goal filtering can miss an actual observation beside an unrelated plan; that conservative limitation is intentional for this bounded change, not a claim of general clinical-language understanding.

## Controlled measurements

At baseline b317975, the exact authored reference passes 3/8 and the saved matched-device transcript passes 2/8. With this extraction change, those same inputs pass 8/8 and 6/8 respectively. Reference, ASR transcript, scorer, normalizer and eight expectations are unchanged. The two remaining saved-ASR failures are tourniquet and tranexamic acid recognition errors. No fuzzy replacement or expected-answer injection is added. This eight-field scenario is a regression control, not proof of general transcription or extraction readiness.

## Final app and device validation

Final simulator integration: 170 tests, three expected skips, zero failures. Skips cover unavailable optional Granite assets and simulator file-protection metadata. Signed physical-device build succeeds and installs on iPhone 17 Pro / iOS 26.2. A fresh on-device run of the existing matched 134.38-second synthetic recording at 2026-09-08T11:52:46Z finalizes and passes 6/8 extraction checks. WER remains 20.74%, with five deletions against 323 normalized reference tokens. Tourniquet and tranexamic acid are the two missed fields. Original audio with an extra unreferenced scenario is not used as a matched accuracy measure.

Private device results and raw transcripts remain outside Git. Only aggregate measurements and synthetic regression cases are published. Live-microphone field acoustics, broader scenarios, and medical-vocabulary ASR improvements remain unvalidated in this sprint. Next work should target those recognition errors without folding wrong words into expected treatments.
