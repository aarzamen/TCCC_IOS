# Capture reliability and truthful export defaults

Approved in the active user conversation on 2026-09-07: capture reliability plus removal of mock export values; Codex leads verification/integration and native Claude Code implements bounded changes.

Ownership updated by the user on 2026-09-08: GPT-6 owns engineering direction and delivery under PROJECT_POLICY.md. Codex may implement directly or delegate; native Claude is optional. Routine commits, pushes, merges and repository publication are authorized. The product and validation contracts below remain in force.

The iOS baseline is 5edde13. Preserve the offline runtime, existing ASR/backend defaults, event-sourced patient state, operator review authority, landscape layout, and protected persistence. Do not migrate models or create a new agent subsystem in this sprint.

## Export contract

A new real encounter contains no invented casualty name, unit, service number, battle-roster number, allergies, or first-responder identity. Unknown values remain blank in the structured DD1380 card and render with the existing empty-field presentation. Explicitly supplied values, including an explicit NKDA, remain valid. Demo fixture text must not become a default for unrelated encounters. Inspect lifecycle boundaries for identity carryover and clear encounter-scoped identity on new/wipe without erasing explicit values within the same encounter. Do not invent a roster/intake implementation or claim persistence of metadata that is not persisted today.

## Capture contract

Benchmark runs distinguish recognizer finalization, incomplete timeout/error/cancellation, and absence of text. Preserve partial evidence without labelling it complete. A finalized recognizer result is not proof that every spoken word was captured. Record callback/result timing and finalization evidence sufficient to compare the file and live paths. Never concatenate cumulative partials as if they were independent utterances.

Live Apple Speech callbacks are scoped to the active capture/request generation. Old callbacks cannot close or contaminate a newer recording. Final-text delivery and rollover occur in one ordered path. Audio arriving after a request is ended must not silently go into a dead request. Normal stop must retain the configured tail and final callback opportunity; abort remains prompt and terminal. Errors and incomplete termination must be observable. Keep the provisional-replace transcript pipeline and patient log semantics intact.

## Validation

Run existing package and app tests, then regression tests that fail against the baseline. Test actual card/PDF output with literal expected values. Use synthetic callback sequences to exercise production capture lifecycle decisions without a microphone/model dependency. Reproduce long-form transcription with the available iPhone and existing authored fixture if accessible; report device/model/recording limits honestly. Preserve device encounter data before any test installation. Do not treat simulated callbacks, successful compilation, or the historical benchmark as proof of current acoustic accuracy.
